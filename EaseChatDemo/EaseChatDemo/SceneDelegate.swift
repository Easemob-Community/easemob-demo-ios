//
//  SceneDelegate.swift
//  EaseChatDemo
//
//  Created by 朱继超 on 2024/3/5.
//

import UIKit
import EaseChatUIKit
import EaseCallUIKit

enum DemoAppearanceMode: String, CaseIterable {
    case system
    case light
    case dark

    static var selected: Self {
        get {
            let defaults = UserDefaults.standard
            if let saved = defaults.string(forKey: "EaseChatDemoAppearanceMode"),
               let mode = Self(rawValue: saved) {
                return mode
            }
            if let darkMode = defaults.object(forKey: "EaseChatDemoDarkMode") as? Bool {
                return darkMode ? .dark : .light
            }
            return .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "EaseChatDemoAppearanceMode")
        }
    }

    var title: String {
        switch self {
        case .system: return "appearance_system".localized()
        case .light: return "appearance_light".localized()
        case .dark: return "appearance_dark".localized()
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    
    @UserDefault("EaseChatDemoPreferencesLanguage", defaultValue: "zh-Hans") var language: String

    @UserDefault("EaseChatDemoUserToken", defaultValue: "") private var token

    @UserDefault("EaseChatDemoUserName", defaultValue: "") private var userName

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene `scene`.
        // If using a storyboard, the `window` property will automatically be initialized and attached to the scene.
        // This delegate does not imply the connecting scene or session are new (see `application:configurationForConnectingSceneSession` instead).
        guard let windowScene = (scene as? UIWindowScene) else { return }
        //设置整个UIKit中的语言 目前只支持中英文
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        
        appearance.backgroundColor = .systemBackground
        let normalAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.secondaryLabel
        ]
        
        let selectedAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.label
        ]
        
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = normalAttributes
        appearance.stackedLayoutAppearance.normal.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: -4)
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = selectedAttributes
        appearance.stackedLayoutAppearance.normal.iconColor = .secondaryLabel
        appearance.stackedLayoutAppearance.selected.iconColor = .label
        // 可选：统一微调文字位置（一般不需要）
        appearance.stackedLayoutAppearance.normal.titlePositionAdjustment =
        UIOffset(horizontal: 0, vertical: 2)
        appearance.stackedLayoutAppearance.selected.titlePositionAdjustment =
        UIOffset(horizontal: 0, vertical: 2)
        
        // ===== 全局生效 =====
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        //设置整个UIKit中的语言 目前只支持中英文
        Appearance.ease_chat_language = LanguageType(rawValue: self.language) ?? .Chinese
        let window = UIWindow(windowScene: windowScene)
        self.window = window
        if #available(iOS 17.0, *) {
            window.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (window: UIWindow, _) in
                guard DemoAppearanceMode.selected == .system else { return }
                self?.applyTheme(window.traitCollection.userInterfaceStyle)
            }
        }
        self.applyAppearancePreference()
        self.chooseRootViewController()
        window.makeKeyAndVisible()
        NotificationCenter.default.addObserver(self, selector: #selector(loadMain), name: Notification.Name(loginSuccessfulSwitchMainPage), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(loadLogin), name: Notification.Name(backLoginPage), object: nil)
    }
    
    func applyAppearancePreference() {
        guard let window, let windowScene = window.windowScene else { return }
        let windowStyle = DemoAppearanceMode.selected.interfaceStyle
        window.overrideUserInterfaceStyle = windowStyle
        for otherWindow in windowScene.windows where otherWindow !== window {
            otherWindow.overrideUserInterfaceStyle = windowStyle
        }
        let effectiveStyle = windowStyle == .unspecified ? windowScene.traitCollection.userInterfaceStyle : windowStyle
        self.applyTheme(effectiveStyle)
    }

    private func applyTheme(_ interfaceStyle: UIUserInterfaceStyle) {
        let dark = interfaceStyle == .dark
        let chatStyle: EaseChatUIKit.ThemeStyle = dark ? .dark : .light
        let callStyle: EaseCallUIKit.ThemeStyle = dark ? .dark : .light
        if EaseCallUIKit.Theme.style != callStyle {
            EaseCallUIKit.Theme.switchTheme(style: callStyle)
        }
        if EaseChatUIKit.Theme.style != chatStyle {
            EaseChatUIKit.Theme.switchTheme(style: chatStyle)
        }
        self.window?.backgroundColor = dark ? UIColor.theme.neutralColor1 : UIColor.theme.neutralColor98
    }

    func windowScene(_ windowScene: UIWindowScene, didUpdate previousCoordinateSpace: UICoordinateSpace,
                     interfaceOrientation previousInterfaceOrientation: UIInterfaceOrientation,
                     traitCollection previousTraitCollection: UITraitCollection) {
        if #available(iOS 17.0, *) { return }
        let style = windowScene.traitCollection.userInterfaceStyle
        if DemoAppearanceMode.selected == .system, previousTraitCollection.userInterfaceStyle != style {
            self.applyTheme(style)
        }
    }
    
    private func chooseRootViewController() {
        //SDK 5.0移除了自动登录,登录凭证由业务侧保存,每次启动需要显式登录
        let userId = self.userName.isEmpty ? (ChatClient.shared().currentUsername ?? ""):self.userName
        guard !self.token.isEmpty,!userId.isEmpty else {
            self.window?.rootViewController = LoginViewController()
            return
        }
        self.window?.rootViewController = MainViewController()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
        self.applyAppearancePreference()
        ChatClient.shared().applicationWillEnterForeground(UIApplication.shared)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
        ChatClient.shared().applicationDidEnterBackground(UIApplication.shared)
    }

    @objc private func loadMain() {
        DispatchQueue.main.async {
            if self.window?.rootViewController is LoginViewController {
                self.window?.rootViewController = MainViewController()
            }
        }
    }
    
    @objc private func loadLogin() {
        ChatUIKitClient.shared.logout(unbindNotificationDeviceToken: true) { error in
            if error != nil {
                consoleLogInfo("Logout failed:\(error?.errorDescription ?? "")", type: .error)
                ChatUIKitClient.shared.logout(unbindNotificationDeviceToken: false) { _ in }
            }
        }
        UserDefaults.standard.removeObject(forKey: "EaseChatDemoUserName")
        UserDefaults.standard.removeObject(forKey: "EaseChatDemoUserToken")
        CallKitManager.shared.hangup()
        CallKitManager.shared.cleanUserDefaults()
        DispatchQueue.main.async {
            self.window?.rootViewController = LoginViewController()
        }
    }
}
