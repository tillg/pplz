#if canImport(Contacts)
import Contacts

/// The labels the edit screen offers per kind of field: the address book's own constants, so that they are shown
/// in the user's language and read back unchanged. A label a contact already has (a custom one) is offered as well.
public enum ContactLabels {
    public static var phone: [String] {
        [CNLabelPhoneNumberMobile, CNLabelPhoneNumberiPhone, CNLabelHome, CNLabelWork, CNLabelPhoneNumberMain, CNLabelPhoneNumberHomeFax,
         CNLabelPhoneNumberWorkFax, CNLabelPhoneNumberOtherFax, CNLabelPhoneNumberPager, CNLabelOther]
    }
    public static var email: [String] { [CNLabelHome, CNLabelWork, CNLabelOther] }
    public static var url: [String] { [CNLabelURLAddressHomePage, CNLabelHome, CNLabelWork, CNLabelOther] }
    public static var address: [String] { [CNLabelHome, CNLabelWork, CNLabelOther] }
    /// Social profiles are labelled by their service.
    public static var socialProfile: [String] {
        [CNSocialProfileServiceTwitter, CNSocialProfileServiceFacebook, CNSocialProfileServiceLinkedIn, CNSocialProfileServiceFlickr,
         CNSocialProfileServiceMySpace, CNSocialProfileServiceSinaWeibo, CNSocialProfileServiceTencentWeibo, CNSocialProfileServiceYelp,
         CNSocialProfileServiceGameCenter]
    }

    /// The label as shown, e.g. `mobile` for `_$!<Mobile>!$_`; a custom label as it is.
    public static func display(_ label: String) -> String {
        label.isEmpty ? "" : CNLabeledValue<NSString>.localizedString(forLabel: label)
    }

    /// The offered labels, plus this one if it is not among them.
    public static func options(_ labels: [String], including current: String) -> [String] {
        current.isEmpty || labels.contains(current) ? labels : labels + [current]
    }
}
#endif
