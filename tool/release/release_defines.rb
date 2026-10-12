# Garde-fou des builds de RELEASE mobile (lanes Fastlane iOS et Android).
#
# Les réglages de build (APP_ENV, achat intégré, identifiant App Store) vivent
# dans `dart-defines.prod.json` (gitignoré ; modèle versionné :
# `dart-defines.prod.example.json`). Sans eux, `APP_ENV` retombe sur `dev` et
# une app publiée afficherait le badge « DEV/STAGING ». Le build est donc refusé
# tant que ce fichier est absent ou incohérent.
#
# Vérifier : ruby tool/release/release_defines_test.rb
require "json"

module ReleaseDefines
  FILE = "dart-defines.prod.json"

  # Réglages réservés aux builds de test : jamais dans un binaire publié
  # (identifiants du compte de test, bascule staging / émulateur).
  FORBIDDEN = /\A(TEST_|MOBILE_STAGING\z|USE_FIREBASE_EMULATOR\z)/

  # Clé SDK RevenueCat attendue par plateforme, et son préfixe (une clé
  # `test_…` du Test Store ne doit jamais partir en production).
  STORE_KEYS = {
    ios: ["REVENUECAT_APPLE_API_KEY", "appl_"],
    android: ["REVENUECAT_GOOGLE_API_KEY", "goog_"],
  }.freeze

  # Rend [erreurs, avertissements] pour le contenu décodé du fichier.
  def self.problems(defines, platform)
    errors = []
    warnings = []
    errors << %(APP_ENV doit valoir "prod") unless defines["APP_ENV"] == "prod"
    defines.keys.grep(FORBIDDEN).each do |key|
      errors << "#{key} est réservé aux builds de test"
    end
    if defines["IAP_ENABLED"].to_s == "true"
      key, prefix = STORE_KEYS.fetch(platform)
      unless defines[key].to_s.start_with?(prefix)
        errors << "IAP_ENABLED=true exige #{key} (clé « #{prefix}… »)"
      end
    end
    if platform == :ios && defines["APP_STORE_ID"].to_s.empty?
      warnings << "APP_STORE_ID vide : « Noter l'app » sera masqué sur iOS"
    end
    [errors, warnings]
  end

  # Arguments `flutter build` d'un build de release, ou échec explicite.
  def self.flutter_args!(root, platform)
    path = File.join(root, FILE)
    unless File.exist?(path)
      raise "#{FILE} absent : copier dart-defines.prod.example.json " \
            "et le renseigner"
    end
    errors, warnings = problems(JSON.parse(File.read(path)), platform)
    warnings.each { |warning| warn "⚠️  #{warning}" }
    raise "#{FILE} invalide : #{errors.join(' ; ')}" unless errors.empty?
    ["--dart-define-from-file=#{FILE}"]
  end
end
