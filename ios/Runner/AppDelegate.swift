import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // Para iOS 9+: Lidar com deep links
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    // Processar o URL do scheme flutterfaceid
    return handleDeepLink(url: url)
  }
  
  // Método para processar o deep link
  private func handleDeepLink(url: URL) -> Bool {
    // Verificar se é o nosso esquema
    if url.scheme == "flutterfaceid" {
      // Adicional: você pode enviar esta informação para o Flutter através de um canal de método
      return true
    }
    return false
  }
}
