import Foundation
@preconcurrency import RimeEngineC

extension RimeContext {
    /// 后台初始化引擎，回主线程创建会话并发布 UI 状态。
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
                try self.prepareUserDirectory()
                try self.setupOnce()
                self.setReady(true)
            }.value
            // 预热 session 避免首次按键迟滞；回到主线程创建，保证可观测状态只在主线程写。
            createSessionIfNeeded()
            // 私有容器不会与主应用共享数据，日志标记实际使用的容器。
            self.log("AppGroup \(RimePaths.appGroupContainer != nil ? "shared" : "per-app (self-signed baseline)")")
            self.log("RIME ready")
        } catch {
            log(error.localizedDescription)
        }
    }

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

    private func prepareUserDirectory() throws {
        guard let user = RimePaths.userDataDirectory else {
            throw RimeError.missingDirectory
        }
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        // 内核会在进程退出时释放数据库锁；删除 LOCK 会破坏仍在使用的 inode 的互斥。
        try ensureInstallationInfo()
    }

    private func setupOnce() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !isSetup else { return }
        guard let shared = RimePaths.sharedSupportDirectory?.path,
              let user = RimePaths.userDataDirectory?.path else {
            NSLog("RIMEForiOS setupOnce: missing directory shared=%@ user=%@",
                  RimePaths.sharedSupportDirectory?.path ?? "nil" as NSString,
                  RimePaths.userDataDirectory?.path ?? "nil" as NSString)
            throw RimeError.missingDirectory
        }

        var traits = RimeTraits()
        rimeStructInit(&traits)
        rime_ios_configure_modules(&traits)
        setCString(shared, to: &traits.shared_data_dir)
        setCString(user, to: &traits.user_data_dir)
        setCString(RimePaths.sharedSupportDirectory?.appendingPathComponent("build", isDirectory: true).path,
                   to: &traits.prebuilt_data_dir)
        // 键盘只保留 warning/error；不让 glog 另写不受轮转限制的 INFO 文件。
        traits.min_log_level = 1
        setCString("", to: &traits.log_dir)
        setCString("RIME for iOS", to: &traits.distribution_name)
        setCString("rime-ios", to: &traits.distribution_code_name)
        setCString("rime.ios", to: &traits.app_name)

        NSLog("RIMEForiOS RIME setup shared=%@ user=%@", shared as NSString, user as NSString)
        rimeAPI.setup!(&traits)
        rimeAPI.initialize!(&traits)
        // 自定义输入模块列表会覆盖 deployer_initialize 的默认部署模块。
        // 清空后加载 deployer/levers，注册同步任务而不执行全量部署。
        traits.modules = nil
        rimeAPI.deployer_initialize!(&traits)

        isSetup = true
        NSLog("RIMEForiOS RIME setup complete")
    }

    func createSessionIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard isReady else { return }
        if session == 0 {
            createSession()
        } else if !rimeAPI.find_session!(session) {
            // librime 可能已清理会话，先丢弃关联的组合和提交状态再重建。
            log("stale session detected, recreating")
            destroySession()
            createSession()
        }
    }

    private func createSession() {
        session = rimeAPI.create_session!()
        NSLog("RIMEForiOS RIME session created: %lu", session)
        selectDefaultSchema()
    }

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
        literalComposition = nil
        commitText = ""
        setContext(candidates: [], preedit: "", highlighted: 0)
        guard session != 0 else { return }
        _ = rimeAPI.destroy_session!(session)
        session = 0
        log("session destroyed")
    }

    /// 维护结束后重建会话；持锁确认没有组合或未消费提交。
    public func recreateSession() {
        lock.lock()
        defer { lock.unlock() }
        guard isReady, commitText.isEmpty, literalComposition == nil else { return }
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
