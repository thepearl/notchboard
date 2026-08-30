//
//  MainActivity.java
//  NotchDemoAndroid
//
//  A minimal screen whose only job is to prove Notchboard's adb deeplink bridge end to
//  end: Notchboard runs `adb shell am start -a android.intent.action.VIEW -d
//  'notchdemo://debug/login?user=…&pass=…'`, this activity receives the intent, and
//  "signs in" as that user — the Android twin of SampleApp/NotchDemo.
//
//  The integration a real app needs is the VIEW intent filter in the manifest plus the
//  ~15 lines of handleDeeplink below. The password is shown masked, mirroring the iOS
//  demo's SecureField.
//

package com.flourix.notchdemo;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Typeface;
import android.net.Uri;
import android.os.Bundle;
import android.util.TypedValue;
import android.view.Gravity;
import android.widget.TextView;

public class MainActivity extends Activity {
    private TextView label;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        label = new TextView(this);
        label.setGravity(Gravity.CENTER);
        label.setTextSize(TypedValue.COMPLEX_UNIT_SP, 17);
        label.setTypeface(Typeface.MONOSPACE);
        int pad = (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, 24, getResources().getDisplayMetrics());
        label.setPadding(pad, pad, pad, pad);
        setContentView(label);
        handleDeeplink(getIntent());
    }

    // launchMode="singleTop": a second login lands here and switches accounts in place.
    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        handleDeeplink(intent);
    }

    // Handles notchdemo://debug/login?user=<username>&pass=<password>.
    // pass is optional — username-only catalogues still prefill the login.
    private void handleDeeplink(Intent intent) {
        Uri url = intent != null ? intent.getData() : null;
        if (url == null) {
            label.setText("brewly\n\ndemo target for the notchboard deeplink\n\nnotchdemo://debug/login?user=…&pass=…");
            return;
        }
        String user = url.getQueryParameter("user");
        if (!"debug".equals(url.getHost()) || !"/login".equals(url.getPath()) || user == null || user.isEmpty()) {
            label.setText("unhandled URL:\n" + url);
            return;
        }
        String pass = url.getQueryParameter("pass");
        label.setText("⚡ signed in via notchboard deeplink\n\n" + user + "\n\n"
                + (pass != null ? "password: " + bullets(pass.length()) : "no password in the link"));
    }

    // Masked, mirroring the iOS demo's SecureField. (Not String.repeat — that needs a
    // newer runtime than minSdk 24 guarantees.)
    private static String bullets(int count) {
        StringBuilder masked = new StringBuilder();
        for (int i = 0; i < Math.min(count, 20); i++) {
            masked.append('•');
        }
        return masked.toString();
    }
}
