//
//  FacebookAuth.swift
//  FBSDKCoreKit
//
//  Created by Darwin Morocho on 11/10/20.
//

import FBSDKCoreKit
import FBSDKLoginKit
import Flutter
import Foundation

class FacebookAuth: NSObject {
    let loginManager: LoginManager = .init()
    var pendingResult: FlutterResult? = nil
    private var mainWindow: UIWindow? {
        if let applicationWindow = UIApplication.shared.delegate?.window ?? nil {
            return applicationWindow
        }
        
        if #available(iOS 13.0, *) {
            if let scene = UIApplication.shared.connectedScenes.first(where: { $0.session.role == .windowApplication }),
               let sceneDelegate = scene.delegate as? UIWindowSceneDelegate,
               let window = sceneDelegate.window as? UIWindow
            {
                return window
            }
        }
        
        return nil
    }
    
    /*
     handle the platform channel
     */
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]
        
        switch call.method {
        case "login":
            let permissions = args?["permissions"] as! [String]
            let tracking = args?["tracking"] as! String
            let customNonce = args?["nonce"] as? String
            
            login(
                permissions: permissions,
                flutterResult: result,
                tracking: tracking == "limited" ? .limited : .enabled,
                nonce: customNonce
            )
            
        case "getAccessToken":
            
            if let token = AccessToken.current, !token.isExpired {
                let accessToken = getAccessToken(
                    accessToken: token,
                    authenticationToken: AuthenticationToken.current,
                    isLimitedLogin: isLimitedLogin()
                )
                result(accessToken)
            } else if let authToken = AuthenticationToken.current {
                let accessToken = getAccessToken(
                    accessToken: nil,
                    authenticationToken: authToken,
                    isLimitedLogin: isLimitedLogin()
                )
                result(accessToken)
            }else {
                result(nil)
            }
            
        case "getUserData":
            let fields = args?["fields"] as! String
            getUserData(fields: fields, flutterResult: result)
            
        case "logOut":
            loginManager.logOut()
            result(nil)
            
        case "updateAutoLogAppEventsEnabled":
            let enabled = args?["enabled"] as! Bool
            updateAutoLogAppEventsEnabled(enabled: enabled, flutterResult: result)
            
        case "isAutoLogAppEventsEnabled":
            let enabled: Bool = Settings.shared.isAutoLogAppEventsEnabled
            result(enabled)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    /*
     use the facebook sdk to request a login with some permissions
     */
    private func login(
        permissions: [String],
        flutterResult: @escaping FlutterResult,
        tracking: LoginTracking,
        nonce: String?
    ) {
        let isOK = setPendingResult(methodName: "login", flutterResult: flutterResult)
        if !isOK {
            return
        }
        
        let isLimitedLogin = _DomainHandler.sharedInstance().isDomainHandlingEnabled() && !Settings.shared.isAdvertiserTrackingEnabled
        
        let permissionSet = Set(permissions.map { Permission(name: $0) })
        
        guard let configuration = LoginConfiguration(
            permissions: permissionSet,
            tracking: isLimitedLogin ? .limited : tracking,
            nonce: nonce ?? UUID().uuidString
        )
        else {
            return
        }
        
        let viewController: UIViewController = (mainWindow?.rootViewController)!
        
        loginManager.logIn(
            configuration: configuration,
            from: viewController,
            handler: { [weak self] loginResult, error in
                guard let self = self else {
                    return
                }
                
                if let error = error {
                    self.finishWithError(errorCode: "FAILED", message: error.localizedDescription)
                } else if loginResult?.isCancelled ?? true {
                    self.finishWithError(errorCode: "CANCELLED", message: "User has cancelled login with facebook")
                } else {
                    // Success
                    let token = loginResult!.token
                    self.setIsLimitedLogin(isLimitedLogin)
                    self.finishWithResult(
                        data: self.getAccessToken(
                            accessToken: token,
                            authenticationToken: AuthenticationToken.current,
                            isLimitedLogin: isLimitedLogin
                        )
                    )
                }
            }
        )
    }
    
    /**
     retrive the user data from facebook, this could be fail if you are trying to get data without the user autorization permission
     */
    private func getUserData(fields: String, flutterResult: @escaping FlutterResult) {
        let graphRequest = GraphRequest(graphPath: "me", parameters: ["fields": fields])
        graphRequest.start { _, result, error in
            if error != nil {
                self.sendErrorToClient(result: flutterResult, errorCode: "FAILED", message: error!.localizedDescription)
            } else {
                let resultDic = result as! NSDictionary
                flutterResult(resultDic) // send the response to the client
            }
        }
    }
    
    /**
     Enable or disable the AutoLogAppEvents
     */
    private func updateAutoLogAppEventsEnabled(enabled: Bool, flutterResult: @escaping FlutterResult) {
        Settings.shared.isAutoLogAppEventsEnabled = enabled
        flutterResult(nil)
    }
    
    // define a login task
    private func setPendingResult(methodName: String, flutterResult: @escaping FlutterResult) -> Bool {
        if pendingResult != nil { // if we have a previous login task
            sendErrorToClient(result: pendingResult!, errorCode: "OPERATION_IN_PROGRESS", message: "The method \(methodName) called while another Facebook login operation was in progress.")
            return false
        }
        pendingResult = flutterResult
        return true
    }
    
    // send the success response to the client
    private func finishWithResult(data: Any?) {
        if pendingResult != nil {
            pendingResult!(data)
            pendingResult = nil
        }
    }
    
    // handle the login errors
    private func finishWithError(errorCode: String, message: String) {
        if pendingResult != nil {
            sendErrorToClient(result: pendingResult!, errorCode: errorCode, message: message)
            pendingResult = nil
        }
    }
    
    // sends a error response to the client
    private func sendErrorToClient(result: FlutterResult, errorCode: String, message: String) {
        result(FlutterError(code: errorCode, message: message, details: nil))
    }
    
    /**
     get the access token data as a Dictionary
     */
    private func getAccessToken(
        accessToken: AccessToken?,
        authenticationToken: AuthenticationToken?,
        isLimitedLogin: Bool
    ) -> [String: Any] {
        print(isLimitedLogin)
        if isLimitedLogin || accessToken == nil {
            if let authToken = authenticationToken {
                let claims = authToken.claims
                return [
                    "type": "limited",
                    "userId": claims["sub"] as? String,
                    "userEmail": claims["email"] as? String,
                    "userName": claims["name"] as? String,
                    "token": authToken.tokenString,
                    "nonce": authToken.nonce,
                ]
            } else {
                return [:] // Fallback empty dict if no token
            }
        }
        
        return [
            "type": "classic",
            "token": accessToken!.tokenString,
            "userId": accessToken!.userID,
            "expires": Int64((accessToken!.expirationDate.timeIntervalSince1970 * 1000).rounded()),
            "applicationId": accessToken!.appID,
            "grantedPermissions": accessToken!.permissions.map { $0.name },
            "declinedPermissions": accessToken!.declinedPermissions.map { $0.name },
            "authenticationToken": authenticationToken?.tokenString,
        ] as [String: Any]
    }
    
    private func setIsLimitedLogin(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: "facebook_limited_login")
    }
        
    private func isLimitedLogin() -> Bool {
        return UserDefaults.standard.bool(forKey: "facebook_limited_login")
    }
}