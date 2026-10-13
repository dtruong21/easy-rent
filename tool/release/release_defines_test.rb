# Vérification de release_defines.rb.
# Lancer : ruby tool/release/release_defines_test.rb
require_relative "release_defines"
require "tmpdir"

def check(label, ok)
  raise "ÉCHEC : #{label}" unless ok
end

def errors(defines, platform = :android)
  ReleaseDefines.problems(defines, platform).first
end

def warnings(defines, platform)
  ReleaseDefines.problems(defines, platform).last
end

def raises?(pattern)
  yield
  false
rescue StandardError => e
  e.message.match?(pattern)
end

PROD = { "APP_ENV" => "prod", "IAP_ENABLED" => "false" }.freeze

check "réglages de prod valides → aucune erreur", errors(PROD).empty?
check "APP_ENV absent → erreur", errors({}).any? { |e| e.include?("APP_ENV") }
check "APP_ENV=dev → erreur",
      errors(PROD.merge("APP_ENV" => "dev")).any? { |e| e.include?("APP_ENV") }

%w[MOBILE_STAGING USE_FIREBASE_EMULATOR TEST_AUTO_LOGIN_EMAIL
   TEST_AUTO_LOGIN_PASSWORD].each do |key|
  check "#{key} → refusé, même à false",
        errors(PROD.merge(key => "false")).any? { |e| e.include?(key) }
end

iap = PROD.merge("IAP_ENABLED" => "true")
check "achat intégré sans clé → erreur",
      errors(iap).any? { |e| e.include?("REVENUECAT_GOOGLE_API_KEY") }
check "achat intégré (booléen JSON) sans clé → erreur",
      errors(PROD.merge("IAP_ENABLED" => true)).any?
check "clé Android valide → aucune erreur",
      errors(iap.merge("REVENUECAT_GOOGLE_API_KEY" => "goog_abc")).empty?
check "clé de test RevenueCat → erreur",
      errors(iap.merge("REVENUECAT_GOOGLE_API_KEY" => "test_abc")).any?
check "clé Apple dans un build Android → erreur",
      errors(iap.merge("REVENUECAT_APPLE_API_KEY" => "appl_abc")).any?
check "clé Apple valide sur iOS → aucune erreur",
      errors(iap.merge("REVENUECAT_APPLE_API_KEY" => "appl_abc"), :ios).empty?
check "achat intégré coupé → clé non exigée", errors(PROD, :ios).empty?

check "iOS sans APP_STORE_ID → avertissement, pas d'erreur",
      warnings(PROD, :ios).any? { |w| w.include?("APP_STORE_ID") }
check "iOS avec APP_STORE_ID → aucun avertissement",
      warnings(PROD.merge("APP_STORE_ID" => "123"), :ios).empty?
check "Android → APP_STORE_ID jamais réclamé", warnings(PROD, :android).empty?

Dir.mktmpdir do |root|
  file = File.join(root, ReleaseDefines::FILE)
  check "fichier absent → échec explicite",
        raises?(/absent/) { ReleaseDefines.flutter_args!(root, :android) }

  File.write(file, JSON.generate(PROD.merge("APP_ENV" => "dev")))
  check "fichier invalide → échec qui nomme le réglage",
        raises?(/APP_ENV/) { ReleaseDefines.flutter_args!(root, :android) }

  File.write(file, JSON.generate(PROD))
  check "fichier valide → argument flutter",
        ReleaseDefines.flutter_args!(root, :android) ==
          ["--dart-define-from-file=dart-defines.prod.json"]
end

modele = File.expand_path("../../dart-defines.prod.example.json", __dir__)
check "le modèle versionné passe la vérification",
      errors(JSON.parse(File.read(modele)), :ios).empty?

puts "release_defines : OK"
