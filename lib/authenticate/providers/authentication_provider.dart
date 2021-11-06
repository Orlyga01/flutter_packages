import 'dart:developer';
import 'dart:io';

import 'package:authentication/shared/helpers/secureStorage.dart';
import 'package:authentication/authenticate/models/login.dart';
import 'package:authentication/authenticate/providers/import_auth.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class AuthenticationNotifier extends StateNotifier<AuthenticationState> {
  AuthenticationNotifier() : super(Uninitialized());

  Future<void> appStarted() async {
    LoginInfo? logininfo;

    try {
      await UserLocalStorage().init();
      logininfo = UserLocalStorage().getLoginData();

      if (logininfo.uid == null || logininfo.loggedOut == null) {
        state = NeedToRegister();
        return;
      } else if (logininfo.loggedOut!) {
        state = NeedToLogin(logininfo);
        return;
      }
      login(logininfo);
    } catch (e) {
      state = Unauthenticated(e.toString(), logininfo);
    }
  }

  afterSuccessfulLogin() {
    state = AfterSuccessfulLogin();
  }

  Future<void> login(LoginInfo logininfo, [bool fromRegister = false]) async {
    state = AuthenticationInProgress();
    logininfo.externalLogin = false;
    await UserLocalStorage().setLoginData(logininfo);
    state = await AuthenticationController()
        .checkCredentials(logininfo, fromRegister);
  }

  Future<void> GoogleLogin() async {
    state = GoogleAuthenticationInProgress();
    state = await AuthenticationController().googleLogin();
  }

  Future<void> AppleLogin() async {
    state = AppleAuthenticationInProgress();
    state = await AuthenticationController().appleLogin();
  }

  userWantsToLogin() {
    state = NeedToLogin(null);
  }

  resetState() {
    state = idleState();
  }
}

class AuthenticationController {
  static final AuthenticationController _groupC =
      new AuthenticationController._internal();
  AuthenticationController._internal();
  FirebaseAuthRepository _authRepository = FirebaseAuthRepository();

  factory AuthenticationController() {
    return _groupC;
  }

  Future<AuthenticationState> checkCredentials(LoginInfo logininfo,
      [bool fromRegister = false]) async {
    UserCredential? userc;
    //That means
    try {
      if (fromRegister)
        userc = await _authRepository.signUp(logininfo);
      else
        userc = await _authRepository.logInWithEmailAndPassword(logininfo);
      logininfo.uid = userc!.user!.uid;
      //If its the same user as before login
      if (isDifferentLoginUser(userc))
        await UserLocalStorage()
            .setLoginData(convertUserCredentialsToLoginInfo(userc, false));
      await UserLocalStorage().setKeyValue("loggedOut", "false");
      log("after credentials success");
      return Authenticated(userc.user!);
    } catch (e) {
      return Unauthenticated(e.toString(), logininfo);
    }
  }

  bool isDifferentLoginUser(UserCredential userc) {
    LoginInfo oldLogin = UserLocalStorage().getLoginData();
    //If its the same user as before login
    return oldLogin.uid != userc.user!.uid;
  }

  Future<AuthenticationState> appleLogin() async {
    if (!await SignInWithApple.isAvailable()) {
      return AppleUnauthenticated(
        'This Device is not eligible for Apple Sign in',
      ); //Break from the program
    }

    try {
      AuthorizationCredentialAppleID credential =
          await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        webAuthenticationOptions: WebAuthenticationOptions(
          // TODO: Set the `clientId` and `redirectUri` arguments to the values you entered in the Apple Developer portal during the setup
          clientId: 'OrlyReznikAppleLogin',
          redirectUri: Uri.parse(
            'https://com.bemember.glitch.me/callbacks/sign_in_with_apple',
          ),
        ),
      );
      final signInWithAppleEndpoint = Uri(
        scheme: 'https',
        host: 'com.bemember.glitch.me',
        path: '/sign_in_with_apple',
        queryParameters: <String, String>{
          'code': credential.authorizationCode,
          if (credential.givenName != null) 'firstName': credential.givenName!,
          if (credential.familyName != null) 'lastName': credential.familyName!,
          'useBundleId': Platform.isIOS || Platform.isMacOS ? 'true' : 'false',
          if (credential.state != null) 'state': credential.state!,
        },
      );
      final session = await http.Client().post(
        signInWithAppleEndpoint,
      );
      final oAuthCredential = OAuthProvider('apple.com').credential(
        idToken: credential.identityToken,
        accessToken: credential.authorizationCode,
      );

// Use the OAuthCredential to sign in to Firebase.
      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(oAuthCredential);
      if (userCredential != null) {
        await afterExternalLogin(userCredential);
        return AppleAuthenticated(userCredential.user!);
      } else {
        return AppleUnauthenticated("Apple Login failed");
      }
    } catch (e) {
      return AppleUnauthenticated(e.toString());
    }
  }

  LoginInfo convertUserCredentialsToLoginInfo(
      UserCredential userc, bool exteranLogin) {
    return LoginInfo(
        email: userc.user!.email,
        uid: userc.user!.uid,
        phone: userc.user!.phoneNumber,
        externalLogin: exteranLogin);
  }

  Future<void> afterExternalLogin(UserCredential userc) async {
    String? personid;
    //check if user exists in the app
    if (isDifferentLoginUser(userc)) {
      await UserLocalStorage()
          .setLoginData(convertUserCredentialsToLoginInfo(userc, true));
    }
    UserLocalStorage().setKeyValue("loggedOut", "false");
  }

  Future<AuthenticationState> googleLogin() async {
    String? personid;
    try {
      UserCredential userc = await _authRepository.logInWithGoogle();
      if (userc != null) {
        await afterExternalLogin(userc);

        return GoogleAuthenticated(userc.user!);
      } else {
        return GoogleUnauthenticated("Google Login failed", null);
      }
    } catch (e) {
      return GoogleUnauthenticated(e.toString(), null);
    }
  }

  LoginInfo getLoginInfoFromLocal() {
    return UserLocalStorage().getLoginData();
  }

  Future<String> sendResetPassword(email) async {
    return _authRepository.resetPassword(email);
  }

  // logOut() async {
  //   UserLocalStorage _localstorage = UserLocalStorage();

  //   LoginInfo? loginInfo = await _localstorage.getLoginData();
  //   await _localstorage.setKeyValue("loggedOut", true.toString());
  //   UserController().resetUser();
  // }
}