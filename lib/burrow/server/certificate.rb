# frozen_string_literal: true

require "openssl"
require "fileutils"

module Burrow
  module Server
    module Certificate
      def self.ensure_pair(directory)
        cert_path, key_path = File.join(directory, "server.crt"), File.join(directory, "server.key")
        return [cert_path, key_path] if File.file?(cert_path) && File.file?(key_path)
        raise ArgumentError, "Keep the existing certificate and its matching key together." if File.exist?(cert_path) || File.exist?(key_path)
        FileUtils.mkdir_p(directory, mode: 0o700)
        key = OpenSSL::PKey::EC.generate("prime256v1")
        cert = OpenSSL::X509::Certificate.new
        cert.version, cert.serial = 2, SecureRandom.random_number(2**120)
        cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/CN=Burrow Brigade self-hosted server")
        cert.public_key = key
        cert.not_before, cert.not_after = Time.now - 60, Time.now + 365 * 24 * 60 * 60 * 3
        factory = OpenSSL::X509::ExtensionFactory.new
        factory.subject_certificate = factory.issuer_certificate = cert
        cert.add_extension(factory.create_extension("basicConstraints", "CA:FALSE", true))
        cert.add_extension(factory.create_extension("keyUsage", "digitalSignature", true))
        cert.add_extension(factory.create_extension("extendedKeyUsage", "serverAuth"))
        cert.sign(key, OpenSSL::Digest::SHA256.new)
        File.write(key_path, key.to_pem, mode: "w", perm: 0o600)
        File.write(cert_path, cert.to_pem, mode: "w", perm: 0o644)
        [cert_path, key_path]
      end
    end
  end
end
