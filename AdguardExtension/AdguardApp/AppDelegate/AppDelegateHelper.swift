/**
    This file is part of Adguard for iOS (https://github.com/AdguardTeam/AdguardForiOS).
    Copyright © Adguard Software Limited. All rights reserved.
 
    Adguard for iOS is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.
 
    Adguard for iOS is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.
 
    You should have received a copy of the GNU General Public License
    along with Adguard for iOS.  If not, see <http://www.gnu.org/licenses/>.
 */

import Foundation
import Setapp

/**
 AppDelegateHelper is a helper class for AppDelegate
 all new functions we must write in this swift class instead of old obj-c AppDelegate
 */

@objcMembers
class AppDelegateHelper: NSObject {
    
    let appDelegate: AppDelegate
    lazy var userNotificationService: UserNotificationServiceProtocol =  { ServiceLocator.shared.getService()! }()
    lazy var resources: AESharedResourcesProtocol = { ServiceLocator.shared.getService()! }()
    lazy var themeService: ThemeServiceProtocol = { ServiceLocator.shared.getService()! }()
    lazy var contentBlockerService: ContentBlockerService = { ServiceLocator.shared.getService()! }()
    lazy var dnsFiltersService: DnsFiltersServiceProtocol = { ServiceLocator.shared.getService()! }()
    lazy var antibannerController: AntibannerControllerProtocol = { ServiceLocator.shared.getService()! }()
    lazy var antibanner: AESAntibannerProtocol = { ServiceLocator.shared.getService()! }()
    lazy var purchaseService: PurchaseServiceProtocol = { ServiceLocator.shared.getService()! }()
    lazy var filtersService: FiltersServiceProtocol =  { ServiceLocator.shared.getService()! }()
    lazy var vpnManager: VpnManagerProtocol = { ServiceLocator.shared.getService()! }()
    lazy var configuration: ConfigurationService = { ServiceLocator.shared.getService()! }()
    lazy var networking: ACNNetworking = { ServiceLocator.shared.getService()! }()
    lazy var activityStatisticsService: ActivityStatisticsServiceProtocol = { ServiceLocator.shared.getService()! }()
    lazy var dnsStatisticsService: DnsStatisticsServiceProtocol = { ServiceLocator.shared.getService()! }()
    lazy var dnsLogRecordsService: DnsLogRecordsServiceProtocol = { ServiceLocator.shared.getService()! }()
    lazy var migrationService: MigrationServiceProtocol = { ServiceLocator.shared.getService()! }()
    lazy var productInfo: ADProductInfoProtocol = { ServiceLocator.shared.getService()! }()
    lazy var rateService: RateAppServiceProtocol = { ServiceLocator.shared.getService()! }()
    lazy var setappService: SetappServiceProtocol = { ServiceLocator.shared.getService()! }()
    lazy var complexProtection: ComplexProtectionServiceProtocol = { ServiceLocator.shared.getService()! }()
    
    private var showStatusBarNotification: NotificationToken?
    private var hideStatusBarNotification: NotificationToken?
    private var orientationChangeNotification: NotificationToken?
    
    private var statusBarWindow: UIWindow?
    private var statusBarIsShown = false
    private let statusView = StatusView()
    
    var purchaseObservation: Any?
    var proStatusObservation: Any?
    
    // MARK: String Constants
    private let openSystemProtection = "systemProtection"
    private let openComplexProtection = "complexProtection"
    private let activateLicense = "license"
    private let subscribe = "subscribe"
    private let openTunnelModeSettings = "openTunnelModeSettings"
    private let applySettings = "apply_settings"
    private let commonUrlScheme = "adguard"
    private let authScheme = "auth"
    private let socialErrorUserNotFound = "user_not_found"
    
    private let dnsFiltersCheckInterval = 21600 // 6 hours
    
    private var firstRun: Bool {
        get {
            resources.sharedDefaults().object(forKey: AEDefaultsFirstRunKey) as? Bool ?? true
        }
        set {
            resources.sharedDefaults().set(newValue, forKey: AEDefaultsFirstRunKey)
        }
    }
    
    @objc var fetchState: BackgroundFetchState {
        get {
            return resources.backgroundFetchState
        }
        set {
            resources.backgroundFetchState = newValue
        }
    }
    
    @objc
    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        super.init()
    }
    
    func applicationDidFinishLaunching(_ application: UIApplication) {
        
        if !Bundle.main.isPro {
            setappService.start()
        }
        
        guard let mainPageController = appDelegate.getMainPageController() else {
            DDLogError("mainPageController is nil")
            return
        }

        mainPageController.onReady = { [weak self] in
            // request permission for user notifications posting
            self?.userNotificationService.requestPermissions()
            
            // Show rate app dialog when main page is initialized
            self?.showRateAppDialogIfNedeed()
        }
        
        guard let dnsLogContainerVC = appDelegate.getDnsLogContainerController() else {
            DDLogError("dnsLogContainerVC is nil")
            return
        }
        /**
         To quickly show stats in ActivityViewController, we load ViewController when app starts
         */
        dnsLogContainerVC.loadViewIfNeeded()
    }
    
    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        
        antibannerController.start()
        
        addPurchaseStatusObserver()
        
        antibannerController.onReady { [weak self] (_) in
            guard let self = self else { return }
            if (self.firstRun) {
                self.migrationService.install()
                self.purchaseService.checkLicenseStatus()
                self.firstRun = false
            }
               
            self.migrationService.migrateIfNeeded(inBackground: self.appDelegate.background)
        }
        
        return true
    }
    
    var statusViewCounter = 0
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        application.applicationIconBadgeNumber = 0
        createStatusBarWindow()
        
        statusBarWindow?.isHidden = true
                
        showStatusBarNotification = NotificationCenter.default.observe(name: NSNotification.Name.ShowStatusView, object: nil, queue: nil, using: {[weak self] (notification) in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.statusViewCounter += 1
                
                if !self.configuration.showStatusBar {
                    return
                }
        
                guard let text = notification.userInfo?[AEDefaultsShowStatusViewInfo] as? String else { return }
                    
                if !self.statusBarIsShown{
                    self.statusBarIsShown = true
                    self.showStatusView(with: text)
                } else {
                    self.changeTextForStatusView(text: text)
                }
            }
        })
        
        hideStatusBarNotification = NotificationCenter.default.observe(name: NSNotification.Name.HideStatusView, object: nil, queue: nil, using: {[weak self] (notification) in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if self.statusViewCounter > 0{
                    self.statusViewCounter -= 1
                }
                
                if self.statusViewCounter == 0 {
                    self.hideStatusView()
                }
            }
        })
        
        orientationChangeNotification = NotificationCenter.default.observe(name: UIDevice.orientationDidChangeNotification, object: nil, queue: nil, using: {[weak self] (notification) in
            DispatchQueue.main.async {
                self?.changeOrientation()
            }
        })
        
        resources.sharedDefaults().addObserver(self, forKeyPath: TunnelErrorCode, options: .new, context: nil)
    }
    
    deinit {
        resources.sharedDefaults().removeObserver(self, forKeyPath: TunnelErrorCode)
    }
    
    // MARK: - Observing Values from User Defaults
       
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == TunnelErrorCode, resources.tunnelErrorCode == 3 {
            postDnsFiltersOverlimitNotificationIfNedeed()
        }
    }
    
    func performFetch() {
        addPurchaseStatusObserver()
    }
    
    func presentDnsFiltersController() -> Bool {
        return appDelegate.presentDnsFiltersController()
    }
    
    /** resets all settings. It removes database and reinit it from default database.
     Also it removes vpn profile. And reomves all keys from keychain (reset authorisation) */
    func resetAllSettings() {
        
        let alert = UIAlertController(title: nil, message: String.localizedString("loading_message"), preferredStyle: .alert)

        let loadingIndicator = UIActivityIndicatorView(frame: CGRect(x: 10, y: 5, width: 50, height: 50))
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.startAnimating();

        alert.view.addSubview(loadingIndicator)
        appDelegate.window.rootViewController?.present(alert, animated: true, completion: nil)
        
        DispatchQueue(label: "reset_queue").async { [weak self] in
            guard let self = self else { return }
            DDLogInfo("(AppDelegate) resetAllSettings")

            self.filtersService.reset()
            self.antibannerController.reset()
            self.vpnManager.removeVpnConfiguration { _ in }
            self.resources.reset()
            self.resetStatistics()
            
            let group = DispatchGroup()
            group.enter()
            
            self.purchaseService.reset {
                group.leave()
            }
            group.wait()
            
            self.dnsFiltersService.reset()
            
            self.appDelegate.setAppInterfaceStyle()
            
            let providersService: DnsProvidersServiceProtocol = ServiceLocator.shared.getService()!
            providersService.reset()
            
            if #available(iOS 14.0, *) {
                let nativeProviders: NativeProvidersServiceProtocol = ServiceLocator.shared.getService()!
                nativeProviders.reset()
            }
            
            // force load filters to fill database
            self.filtersService.load(refresh: true) {}
            
            // Notify that settings were reset
            NotificationCenter.default.post(name: NSNotification.resetSettings, object: self)
            
            DispatchQueue.main.async { [weak self] in
                self?.appDelegate.setMainPageAsCurrentAndPopToRootControllersEverywhere()
            }
        }
    }

    func showCommonAlertForTopVc(_ body: String?, _ title: String?) {
        DispatchQueue.main.async {
            if let topVC = AppDelegate.topViewController() {
                ACSSystemUtils.showSimpleAlert(for: topVC, withTitle: body, message: title)
            }
        }
    }
    
    // MARK: - private methods
    
    private func postDnsFiltersOverlimitNotificationIfNedeed(){
        let rulesNumberString = String.simpleThousandsFormatting(NSNumber(integerLiteral: dnsFiltersService.enabledRulesCount))
        let title = String.localizedString("dns_filters_notification_title")
        let body = String(format: String.localizedString("dns_filters_overlimit_title"), rulesNumberString)
        let userInfo: [String : Int] = [PushNotificationCommands.command : PushNotificationCommands.openDnsFiltersController.rawValue]
        userNotificationService.postNotification(title: title, body: body, userInfo: userInfo)
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        DDLogError("(AppDelegate) application Open URL: \(url.absoluteURL)");
        
        if !Bundle.main.isPro {
            if setappService.openUrl(url, options: options) {
                return true
            }
        }
            
        var command: String?
        var params: [String: String]?
        
        if url.host != nil {
            command = url.host!
            if command == authScheme {
                let result = url.parseAuthUrl()
                params = result.params
            } else if command == subscribe {
                let result = url.parseUrl()
                params = result.params
            }
        } else {
            let result = url.parseUrl()
            command = result.command
            params = result.params
        }
        
        if command == activateLicense && Bundle.main.isPro {
            return false
        }

        let success = process(url: url, command: command, params: params)
        return success
    }
    
    func updateDnsFiltersIfNeeded( callback: @escaping ()->Void) {
        let lastCheckTime = resources.lastDnsFiltersUpdateTime ?? Date(timeIntervalSince1970: 0)
        let interval = Date().timeIntervalSince(lastCheckTime)
        let checkResult = checkAutoUpdateConditions()
        if !dnsFiltersService.filtersAreUpdating
            && Int(interval) > dnsFiltersCheckInterval
            && configuration.proStatus
            && checkResult {
            resources.lastDnsFiltersUpdateTime = Date()
            
            DDLogInfo("(AppDelegateHelper) updateDnsFiltersIfNeeded - update dns filters")
            dnsFiltersService.updateFilters(networking: networking) { [weak self] in
                
                DDLogInfo("(AppDelegateHelper) updateDnsFiltersIfNeeded - dns filters are updeted")
                self?.updateTunnelSettingsIfAppropriate {
                    callback()
                }
            }
        }
        else {
            DDLogInfo("(AppDelegateHelper) updateDnsFiltersIfNeeded - not all conditions are met")
            callback()
        }
    }
    
    func checkAutoUpdateConditions()->Bool {
        
        if !resources.wifiOnlyUpdates {
            return true
        }
        
        let reachability = Reachability.forInternetConnection()
        let reachable = reachability?.isReachableViaWiFi() ?? false
        if !reachable {
            DDLogInfo("(AppDelegateHelper - checkAutoUpdateConditions) App settings permit updates only over WiFi.")
        }
        return reachable
    }
    
    /**
     Do not update VPN configuration if:
     1. System protection is disabled
     2. DNS implementation is native
     3. Application is in background state (we are not sure if VPN configuration is active)
     */
    private func updateTunnelSettingsIfAppropriate(callback: @escaping ()->Void ) {
        vpnManager.getConfigurationStatus { [weak self] (status) in
            guard let self = self else { return }
            if self.complexProtection.systemProtectionEnabled, self.resources.dnsImplementation == .adGuard, status.configurationIsActive, self.dnsFiltersService.enabledFiltersCount > 0 {
                self.vpnManager.updateSettings { _ in
                    callback()
                }
            }
            else {
                callback()
            }
        }
    }
    
    /*
     Processes incoming URL scheme and presents appropriate view controller
     Returns true on success and false otherwise
     Must be executed on main thread
     */
    private func process(url: URL , command: String?, params: [String: String]?) -> Bool {
        let scheme = url.scheme
        
        /*
         When we open an app from action extension we show user a launch screen, while view controllers are being loaded, when they are, we show UserFilterController. It is done by changing app's window.
         https://github.com/AdguardTeam/AdguardForiOS/issues/1135
        */
        switch (scheme, command) {
        
        // Adding new user rule from safari
        case (AE_URLSCHEME, AE_URLSCHEME_COMMAND_ADD) :
            antibannerController.onReady { antibanner in
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    let model: ListOfRulesModelProtocol = UserFilterModel(resources: self.resources, contentBlockerService: self.contentBlockerService, antibanner: self.antibanner, theme: self.themeService, productInfo: self.productInfo)
                    let rule = String(url.path.suffix(url.path.count - 1))
                    self.appDelegate.presentUserFilterController(showLaunchScreen: true, model, newRule: rule)
                }
            }
            return true
            
        // Turning on/off DNS protection from widget
        case (AE_URLSCHEME, openSystemProtection):
            let suffix = String(url.path.suffix(url.path.count - 1))
            let parameters = suffix.split(separator: "/")
            
            let enabledString = String(parameters.first ?? "")
            let enabled = enabledString == "on"
            
            let success = self.appDelegate.presentDnsSettingsController(showLaunchScreen: true, dnsProtectionIsEnabled: enabled)
            return success
            
        // Turning on/off complex protection from widget
        case (AE_URLSCHEME, openComplexProtection):
            let suffix = String(url.path.suffix(url.path.count - 1))
            let parameters = suffix.split(separator: "/")
            
            let enabledString = String(parameters.first ?? "")
            let enabled = enabledString == "on"
            
            let success = appDelegate.presentMainPageController(showLaunchScreen: true, complexProtectionIsEnabled: enabled)
            return success
        
        // Activate license by URL
        case (AE_URLSCHEME, activateLicense):
            DDLogInfo("(AppDelegateHelper) - activate license key from openUrl")
            let license = params?["license"]
            
            if license == nil || license!.isEmpty {
                DDLogInfo("(AppDelegateHelper) - update license from openUrl")
                purchaseService.checkLicenseStatus()
                let success = appDelegate.presentMainPageController()
                return success
            } else {
                DDLogInfo("(AppDelegateHelper) - activate license key from openUrl")
                let success = appDelegate.presentLoginController(showLaunchScreen: true, withLicenseKey: license)
                return success
            }
        
        // Adding custom DNS server
        case (AE_SDNS_SCHEME, _):
            DDLogInfo("(AppDelegateHelper) openurl sdns: \(url.absoluteString)")
            if !configuration.proStatus {
                let success = appDelegate.presentDnsSettingsController()
                return success
            } else {
                let dnsInfo = DnsResolver.resolve(upstream: url.absoluteString)
                guard let dnsServer = dnsInfo.dnsServer else {
                    return false
                }
                let success = appDelegate.presentDnsProvidersController(url: dnsServer)
                return success
            }
            
        case (commonUrlScheme, applySettings):
            DDLogInfo("(AppDelegateHelper) openurl - apply settings")
            let params = url.parseUrl().params
            guard let json = params?["json"] else {
                DDLogError("(AppDelegateHelper) there is no param 'json' in url")
                return false
            }
            let parser = SettingsParser()
            let settings = parser.parse(querry: json)
            let success = appDelegate.presentImportSettingsController(showLaunchScreen: true, settings: settings)
            return success
        
        // Subscribe to custom filter
        case (_, subscribe):
            DDLogInfo("(AppDelegateHelper) openurl - subscribe filter")
            
            let url = params?["location"]?.removingPercentEncoding
            let title = params?["title"]?.removingPercentEncoding
            
            let success = appDelegate.presentFiltersMasterController(showLaunchScreen: true, url: url, title: title)
            return success
            
        case (_, openTunnelModeSettings):
            DDLogInfo("(AppDelegateHelper) openurl - open tunnel mode settings")
            configuration.advancedMode = true
            let success = appDelegate.presentTunnelModeController()
            return success
            
        // Log in by social networks
        case (commonUrlScheme, authScheme):
            DDLogInfo("(AppDelegateHelper) openurl - Log in by social networks")
            if let error = params?["error"] {
                socialLoginErrorProcessor(error: error)
                return false
            } else {
                let token = params?["access_token"]
                let state = params?["state"]
                purchaseService.login(withAccessToken: token, state: state)
                return true
            }

            
        default: return false
        }
    }
    
    private func socialLoginErrorProcessor(error: String) {
        var userInfo = [AnyHashable: Any]()
        DDLogInfo("(AppDelegateHelper) Social login error: \(error)")
        switch error {
        case socialErrorUserNotFound:
            userInfo[PurchaseService.kPSNotificationTypeKey] = PurchaseService.kPSNotificationLoginUserNotFound
            userInfo[PurchaseService.kPSNotificationErrorKey] = NSError(domain: LoginService.loginErrorDomain, code: LoginService.socialUserNotFound, userInfo: nil)
            
        default:
            break
        }
        NotificationCenter.default.post(name: Notification.Name(PurchaseService.kPurchaseServiceNotification), object: self, userInfo: userInfo)

    }
    
    private func addPurchaseStatusObserver() {
        if purchaseObservation == nil {
            purchaseObservation = NotificationCenter.default.observe(name: Notification.Name(PurchaseService.kPurchaseServiceNotification), object: nil, queue: nil) { (notification) in
                guard let type =  notification.userInfo?[PurchaseService.kPSNotificationTypeKey] as? String else { return }
                
                DDLogInfo("(AppDelegateHelper) - Received notification type = \(type)")
                
                if type == PurchaseService.kPSNotificationPremiumExpired {
                    self.userNotificationService.postNotification(title: ACLocalizedString("premium_expired_title", nil), body: ACLocalizedString("premium_expired_message", nil), userInfo: nil)
                }
            }
        }
        
        if proStatusObservation == nil {
            proStatusObservation = configuration.observe(\.proStatus) {[weak self] (_, _) in
                guard let self = self else { return }
                if !self.configuration.proStatus && self.vpnManager.vpnInstalled {
                    DDLogInfo("(AppDelegateHelper) Remove vpn configuration")
                    self.vpnManager.removeVpnConfiguration { (error) in
                        if error != nil {
                            DDLogError("(AppDelegateHelper) Remove vpn configuration failed: \(error!)")
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Methods to deal with statusViewBar
    
    private func createStatusBarWindow(){
        guard let keyWindow = UIApplication.shared.keyWindow else { return }
        let bottomSafeAreaInset = keyWindow.safeAreaInsets.bottom / 2.0
                
        let frame = CGRect(x: 0.0, y: keyWindow.frame.maxY, width: keyWindow.frame.width, height: 16.0 + bottomSafeAreaInset)
        
        let bannerWindow = UIWindow(frame: frame)
        bannerWindow.backgroundColor = UIColor(hexString: "#d8d8d8")
        bannerWindow.windowLevel = UIWindow.Level.statusBar
        bannerWindow.addSubview(statusView)
        bannerWindow.isHidden = false
        
        statusView.translatesAutoresizingMaskIntoConstraints = false
        statusView.topAnchor.constraint(equalTo: bannerWindow.topAnchor).isActive = true
        statusView.leftAnchor.constraint(equalTo: bannerWindow.leftAnchor).isActive = true
        statusView.rightAnchor.constraint(equalTo: bannerWindow.rightAnchor).isActive = true
        statusView.bottomAnchor.constraint(equalTo: bannerWindow.bottomAnchor).isActive = true
        
        statusBarWindow = bannerWindow
    }
    
    private func showStatusView(with text: String?){
        statusBarWindow?.isHidden = false
        
        UIView.animate(withDuration: 0.5) {[weak self] in
            guard let sSelf = self else { return }
            guard let keyWindow = UIApplication.shared.keyWindow else { return }
            
            sSelf.statusView.text = text
            let height = sSelf.statusBarWindow?.frame.height ?? 0.0
            sSelf.statusBarWindow?.frame.origin.y = keyWindow.frame.maxY - height
        }
    }
    
    private func hideStatusView(){
        UIView.animate(withDuration: 0.5, animations: {[weak self] in
            guard let sSelf = self else { return }
            guard let keyWindow = UIApplication.shared.keyWindow else { return }
            
            sSelf.statusBarWindow?.frame.origin.y = keyWindow.frame.maxY
        }) {[weak self] (success) in
            self?.statusBarIsShown = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {[weak self] in
                self?.statusBarWindow?.isHidden = true
            }
        }
    }
    
    private func changeOrientation(){
        UIView.animate(withDuration: 0.5) {[weak self] in
            guard let sSelf = self else { return }
            guard let keyWindow = UIApplication.shared.keyWindow else { return }
            let height = sSelf.statusBarWindow?.frame.height ?? 0.0
            
            if sSelf.statusBarIsShown {
                let frame = CGRect(x: 0.0, y: keyWindow.frame.maxY - height, width: keyWindow.frame.width, height: height)
                sSelf.statusBarWindow?.frame = frame
            } else {
                let frame = CGRect(x: 0.0, y: keyWindow.frame.maxY, width: keyWindow.frame.width, height: height)
                sSelf.statusBarWindow?.frame = frame
            }
        }
    }
    
    private func changeTextForStatusView(text: String){
        DispatchQueue.main.async {[weak self] in
            self?.statusView.text = text
        }
    }
    
    private func resetStatistics(){
        /* Reseting statistics Start*/
        self.activityStatisticsService.stopDb()
        self.dnsStatisticsService.stopDb()
        
        // delete database file
        let url = self.resources.sharedResuorcesURL().appendingPathComponent("dns-statistics.db")
        try? FileManager.default.removeItem(atPath: url.path)
        
        /* Reseting statistics end */
        self.activityStatisticsService.startDb()
        self.dnsStatisticsService.startDb()
        
        self.dnsLogRecordsService.reset()
    }
    
    private func showRateAppDialogIfNedeed() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self else { return }
            if self.rateService.shouldShowRateAppDialog {
                AppDelegate.shared.presentRateAppController()
                self.resources.rateAppShown = true
            }
        }
    }
}

// MARK: - Filter updates methods

extension AppDelegateHelper {
    func updateStartedNotify() {
        ACSSystemUtils.call {
            let appState = UIApplication.shared.applicationState
            DDLogInfo("(AppDelegateHelper) Started update process. AppState = \(appState.rawValue)")
            
            NotificationCenter.default.post(name: .AppDelegateStartedUpdate, object: self)
        }
    }
    
    func updateDidNotStartNotify() {
        ACSSystemUtils.call { [weak self] in
            let appState = UIApplication.shared.applicationState
            DDLogInfo("(AppDelegateHelper) Did not started update process. AppState = \(appState.rawValue)")
            
            NotificationCenter.default.post(name: .AppDelegateUpdateDidNotStarted, object: self)
        }
    }
    
    func updateFailuredNotify() {
        ACSSystemUtils.call { [weak self] in
            let appState = UIApplication.shared.applicationState
            DDLogInfo("(AppDelegateHelper) Failured update process. AppState = \(appState.rawValue)")
            
            NotificationCenter.default.post(name: .AppDelegateFailuredUpdate, object: self)
        }
    }
    
    func updateFinishedNotify(updatedFiltersNumber: Int) {
        ACSSystemUtils.call { [weak self] in
            let appState = UIApplication.shared.applicationState
            DDLogInfo("(AppDelegateHelper) Finished update process, updated filters = \(updatedFiltersNumber). AppState = \(appState.rawValue)")
            
            let userInfo = [AppDelegateUpdatedFiltersKey: updatedFiltersNumber]
            NotificationCenter.default.post(name: .AppDelegateFinishedUpdate, object: self, userInfo: userInfo)
        }
    }
}
