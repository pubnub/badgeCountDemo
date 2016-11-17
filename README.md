# push-demo

**This was best practice on iOS 9 but is no longer best practice for iOS 10, use at your own discretion**

Run "pod install" in root directory of repo to install pods and only open Push.xcworkspace

Need to have proper provisioning profiles and APNS certs. If you need help, go [here.](https://www.pubnub.com/docs/ios-objective-c/mobile-gateway-sdk-v4)

To increment badge count, tap "publish" button in first view controller (from another device or sim!) or run curl command below:

```
curl 'https://ps5.pubnub.com/publish/pub-c-366ee301-3a9a-41ca-b3f2-d9dba11dbd10/sub-c-66eb5ede-fb1c-11e3-bacb-02ee2ddab7fe/0/teddyr/0/%7B%22pn_apns%22%3A%7B%22aps%22%3A%7B%22content-available%22%3A1%7D%7D%7D?uuid=073658ad-c8b2-44c4-9441-b59632b9c427'
```

This will cause the badge to increment for the app on a device (only apps on a device can receive push notifications!).

## Note
This will fail to work under either condition:
* App has not been launched since the last restart
* App was force killed in app switcher

Background execution is kicked off by iOS itself, and is not necessarily instantaneous. It might a few seconds before execution begins, but shouldn't be more than a minute or two. Excecution involves 1 or more history calls, which is an API request. The client gets a maximum of 30 seconds to execute any code before it is stopped. Move quickly!

