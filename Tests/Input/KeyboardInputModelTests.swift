import Testing
import UIKit
import KeyboardModels
@testable import KeyboardUI

@MainActor
struct KeyboardInputModelTests {
    @Test("布局切换只消耗数字/符号页的一次大写")
    func layoutSwitches() {
        for (action, expected) in [(KeyAction.numbers, KeyboardLayout.numbers), (.symbols, .symbols), (.letters, .qwerty)] {
            let model = KeyboardInputModel()
            model.shiftState = .uppercaseOnce
            #expect(model.consume(action) == nil)
            #expect(model.currentLayout == expected)
            #expect(model.shiftState == (action == .letters ? .uppercaseOnce : .lowercase))
        }
    }

    @Test("字母消耗一次大写，锁定保留；编辑草稿不启动组合")
    func characterCase() {
        for state in [ShiftState.uppercaseOnce, .uppercaseLocked] {
            let model = KeyboardInputModel()
            model.shiftState = state
            #expect(model.consume(.character("a")) == .character("A"))
            #expect(model.shiftState == (state == .uppercaseLocked ? .uppercaseLocked : .lowercase))
        }
    }

    @Test("符号输入消耗一次大写，句末符号返回字母页")
    func symbolRouting() {
        for symbol in ["。", "←"] {
            let model = KeyboardInputModel()
            model.currentLayout = .symbols
            model.shiftState = .uppercaseOnce
            #expect(model.consume(.character(symbol)) == .directInput(symbol))
            #expect(model.shiftState == .lowercase)
            #expect(model.currentLayout == (symbol == "。" ? .qwerty : .symbols))
        }
    }

    @Test("所有布局的无组合空格按语言路由，空格和退格保留一次大写")
    func nonCharacterRouting() {
        let model = KeyboardInputModel()
        for language in [InputLanguage.chinese, .english] {
            model.inputLanguage = language
            for layout in KeyboardLayout.allCases {
                model.currentLayout = layout
                model.shiftState = .uppercaseOnce
                #expect(model.consume(.space) == (language == .chinese ? .space : .directInput(" ")))
                #expect(model.shiftState == .uppercaseOnce)
                #expect(model.consume(.backspace) == .backspace)
                #expect(model.shiftState == .uppercaseOnce)
            }
        }
    }

    @Test("切换语言更新大小写，字段类型改变时返回字母页，相同类型不覆盖用户状态")
    func languageAndHostContext() {
        let model = KeyboardInputModel()
        #expect(model.consume(.toggleLanguage) == .toggleLanguage)
        #expect(model.inputLanguage == .english && model.shiftState == .uppercaseOnce)
        #expect(model.consume(.toggleLanguage) == .toggleLanguage)
        #expect(model.inputLanguage == .chinese && model.shiftState == .lowercase)
        model.handleKeyboardTypeChange(.asciiCapable)
        #expect(model.inputLanguage == .english && model.shiftState == .uppercaseOnce)
        model.currentLayout = .symbols
        model.handleKeyboardTypeChange(.default)
        #expect(model.currentLayout == .qwerty && model.inputLanguage == .chinese && model.shiftState == .lowercase)
        model.currentLayout = .symbols
        model.shiftState = .uppercaseLocked
        model.handleKeyboardTypeChange(.default)
        #expect(model.currentLayout == .symbols && model.shiftState == .uppercaseLocked)
    }

    @Test("回车显示宿主语义，组合期统一显示确认符号")
    func returnLabels() {
        let model = KeyboardInputModel()
        let cases: [(UIReturnKeyType, String)] = [(.go, "前往"), (.search, "搜索"), (.send, "发送"), (.next, "下一步"), (.done, "完成"), (.emergencyCall, "紧急呼叫"), (.continue, "继续"), (.default, "换行")]
        for (type, label) in cases {
            model.handleReturnKeyType(type)
            #expect(model.returnKeyLabel == label)
            #expect(KeyboardInputModel.effectiveReturnLabel(hasPreedit: true, hostLabel: label) == "⏎")
            #expect(KeyboardInputModel.effectiveReturnLabel(hasPreedit: false, hostLabel: label) == label)
        }
    }
}
