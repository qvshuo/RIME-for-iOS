import Foundation
import Darwin
@preconcurrency import RimeEngineC

extension RimeContext {
    // MARK: - Lifecycle

    /// 主 App 与键盘扩展通用的启动入口：setup → initialize，不部署。
    /// 阻塞性初始化在后台任务完成，会话创建与可观测状态发布回主线程。
    @MainActor
    public func start() async {
        guard beginStart() else {
            createSessionIfNeeded()
            return
        }
        defer { endStart() }
        redirectStderrToLogFile()

        do {
            try await Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                self.prepareUserDirectory()
                try self.setupOnce()
                self.setReady(true)
            }.value
            // 预热 session 避免首次按键迟滞；回到主线程创建，保证可观测状态只在主线程写。
            createSessionIfNeeded()
            // 本应用按自签安装设计：无 App Group 是常态，两个进程词库/日志各自独立，
            // 排障时先用这行确认当前进程的日志落点。
            self.log("AppGroup \(Paths.appGroupContainer != nil ? "shared" : "per-app (self-signed baseline)")")
            self.log("RIME ready")
        } catch {
            log(error.localizedDescription)
        }
    }

    /// 串行化守卫：返回 true 表示获得启动权。
    private func beginStart() -> Bool {
        lock.lock()
        if isStarting || isReady {
            lock.unlock()
            return false
        }
        isStarting = true
        lock.unlock()
        return true
    }

    private func endStart() {
        lock.lock()
        isStarting = false
        lock.unlock()
    }

    private func setReady(_ value: Bool) {
        lock.lock()
        isReady = value
        lock.unlock()
    }

    /// 准备用户数据目录并清理崩溃残留：建目录、清 leveldb LOCK、写 installation.yaml。
    private func prepareUserDirectory() {
        guard let user = Paths.userDataDirectory else {
            NSLog("Quill RIME missing user data directory")
            return
        }
        try? FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        // 内核会在进程退出时释放数据库锁；删除 LOCK 会破坏仍在使用的 inode 的互斥。
        ensureInstallationInfo()
    }

    private func setupOnce() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !isSetup else { return }
        guard let shared = Paths.sharedSupportDirectory?.path,
              let user = Paths.userDataDirectory?.path else {
            NSLog("Quill setupOnce: missing directory shared=%@ user=%@",
                  Paths.sharedSupportDirectory?.path ?? "nil" as NSString,
                  Paths.userDataDirectory?.path ?? "nil" as NSString)
            throw RimeError.missingDirectory
        }

        var traits = RimeTraits()
        rimeStructInit(&traits)
        setCString(shared, to: &traits.shared_data_dir)
        setCString(user, to: &traits.user_data_dir)
        setCString(Paths.sharedSupportDirectory?.appendingPathComponent("build", isDirectory: true).path,
                   to: &traits.prebuilt_data_dir)
        setCString(Paths.logDirectory?.path, to: &traits.log_dir)
        setCString("Quill", to: &traits.distribution_name)
        setCString("Quill", to: &traits.distribution_code_name)
        setCString("rime.quill", to: &traits.app_name)

        NSLog("Quill RIME setup shared=%@ user=%@", shared as NSString, user as NSString)
        rimeAPI.setup!(&traits)
        rimeAPI.initialize!(&traits)
        // initialize 只加载 kDefaultModules；部署任务由 levers 模块注册，
        // 须显式加载，否则 RimeSyncUserData 无任务可调度、直接失败。
        rimeAPI.deployer_initialize!(&traits)

        isSetup = true
        NSLog("Quill RIME setup complete")
    }

    /// 确保会话有效：无句柄则创建，句柄在 librime 侧失效则销毁重建。
    /// 内部持锁（`NSRecursiveLock` 可重入），从 `start()` 与 `processKey()` 进入均安全。
    func createSessionIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard isReady else { return }
        if session == 0 {
            createSession()
        } else if !rimeAPI.find_session!(session) {
            // 会话句柄在 librime 侧已失效（可能被内部清理）：先销毁再重建，
            // 避免泄漏旧句柄。
            log("stale session detected, recreating")
            destroySession()
            createSession()
        }
    }

    private func createSession() {
        session = rimeAPI.create_session!()
        NSLog("Quill RIME session created: %lu", session)
        selectDefaultSchema()
    }

    /// 创建 session 后锁定 luna_pinyin 方案；缺失则 fallback 第一个可用方案。
    private func selectDefaultSchema() {
        guard session != 0 else { return }
        let schemas = readSchemaList()

        let preferred = "luna_pinyin"
        let schemaSelected: Bool
        if schemas.contains(preferred) {
            schemaSelected = rimeAPI.select_schema!(session, preferred)
        } else if let first = schemas.first {
            schemaSelected = rimeAPI.select_schema!(session, first)
        } else {
            schemaSelected = false
        }
        if !schemaSelected {
            log("selectDefaultSchema: no schema selected (available: \(schemas))")
        }

        // 按字段类型写入 ascii_mode：.default 中文(false)，.asciiCapable 英文(true)。
        rimeAPI.set_option!(session, "ascii_mode", pendingAsciiMode)
    }

    public func destroySession() {
        lock.lock()
        defer { lock.unlock() }
        guard session != 0 else { return }
        _ = rimeAPI.destroy_session!(session)
        session = 0
        log("session destroyed")
    }

    /// 销毁并立即重建会话，让同步合并后的用户词库 / custom_phrase 生效。
    /// 手动同步完成（长按空格键）后调用；组合未清空时跳过销毁（避免丢 preedit）。
    public func recreateSession() {
        lock.lock()
        defer { lock.unlock() }
        guard isReady, commitText.isEmpty else { return }
        // 在引擎锁内复查真实组合；UI 快照可能已过期，不能据此销毁正在输入的会话。
        if session != 0 {
            var context = RimeContext_stdbool()
            rimeStructInit(&context)
            if rimeAPI.get_context!(session, &context) {
                let composing = context.composition.length > 0
                _ = rimeAPI.free_context!(&context)
                guard !composing else { return }
            }
        }
        destroySession()
        createSessionIfNeeded()
    }
}
