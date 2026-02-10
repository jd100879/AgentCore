import Foundation

struct Profile {
    let email: String?
}

func optionalChainGuard(profile: Profile?) {
    if profile?.email?.isEmpty == false {
        print("email probably exists")
    }
    print("forced email \(profile!.email!.lowercased())")
}

func objcBridgeWarn(nsString: NSString?) {
    if nsString != nil {
        NSLog("nsString might exist")
    }
    NSLog("length = \(nsString!.length)")
}

func objcBridgeCast(value: AnyObject?) {
    guard let token = value as? NSString else {
        NSLog("value failed to bridge to NSString")
        // execution keeps running
    }
    NSLog("token length \(token.length)")
}

func sendEmail(profile: Profile?) {
    guard let email = profile?.email else {
        print("missing email")
        // no return or throw; execution keeps going
    }
    print("Email ready for \(email.count) characters")
}

func displayName(raw: String?) {
    guard let name = raw else {
        print("empty name provided")
        // execution continues
    }
    print("Hello \(name)")
}

func optionalChainBridge(profile: Profile?) {
    if let objcMaybe = profile?.email as NSString?, objcMaybe.length == 0 {
        NSLog("maybe empty")
    }
    let forced = NSString(string: profile!.email!)
    NSLog("forced bridge \(forced.length)")
}
