class Dikto < Formula
  desc "Push-to-talk voice dictation for macOS using Whisper"
  homepage "https://github.com/misteral/dikto"
  url "https://github.com/misteral/dikto.git", tag: "v0.9.1"
  license "MIT"

  depends_on "whisper-cpp"
  depends_on :macos

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    system "bash", "scripts/bundle-app.sh", ".build/release/dikto", "Dikto.app", version.to_s
    bin.install ".build/release/dikto"
    prefix.install "Dikto.app"
  end

  def post_install
    target = Pathname.new("#{Dir.home}/Applications/Dikto.app")
    target.dirname.mkpath
    target.rmtree if target.exist?
    cp_r prefix/"Dikto.app", target
    system "codesign", "--remove-signature", "#{target}/Contents/MacOS/dikto"
    system "tccutil", "reset", "Accessibility", "co.itbeaver.dikto"
  end

  service do
    run ["#{Dir.home}/Applications/Dikto.app/Contents/MacOS/dikto", "start"]
    keep_alive successful_exit: false
    log_path var/"log/dikto.log"
    error_log_path var/"log/dikto.log"
    process_type :interactive
  end

  def caveats
    <<~EOS
      Recommended: use the install script for guided setup:
        curl -fsSL https://raw.githubusercontent.com/misteral/dikto/main/scripts/install.sh | bash

      Or start manually:
        brew services start dikto

      Grant Accessibility and Microphone when prompted.
      The Whisper model downloads automatically (~142 MB).
    EOS
  end

  test do
    assert_match "dikto", shell_output("#{bin}/dikto --help")
  end
end
