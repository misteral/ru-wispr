class RuWisper < Formula
  desc "Push-to-talk voice dictation for macOS using Whisper"
  homepage "https://github.com/human37/ru-wisper"
  url "https://github.com/human37/ru-wisper.git", tag: "v0.9.1"
  license "MIT"

  depends_on "whisper-cpp"
  depends_on :macos

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    system "bash", "scripts/bundle-app.sh", ".build/release/ru-wisper", "RuWisper.app", version.to_s
    bin.install ".build/release/ru-wisper"
    prefix.install "RuWisper.app"
  end

  def post_install
    target = Pathname.new("#{Dir.home}/Applications/RuWisper.app")
    target.dirname.mkpath
    target.rmtree if target.exist?
    cp_r prefix/"RuWisper.app", target
    system "codesign", "--remove-signature", "#{target}/Contents/MacOS/ru-wisper"
    system "tccutil", "reset", "Accessibility", "com.human37.ru-wisper"
  end

  service do
    run ["#{Dir.home}/Applications/RuWisper.app/Contents/MacOS/ru-wisper", "start"]
    keep_alive successful_exit: false
    log_path var/"log/ru-wisper.log"
    error_log_path var/"log/ru-wisper.log"
    process_type :interactive
  end

  def caveats
    <<~EOS
      Recommended: use the install script for guided setup:
        curl -fsSL https://raw.githubusercontent.com/human37/ru-wisper/main/scripts/install.sh | bash

      Or start manually:
        brew services start ru-wisper

      Grant Accessibility and Microphone when prompted.
      The Whisper model downloads automatically (~142 MB).
    EOS
  end

  test do
    assert_match "ru-wisper", shell_output("#{bin}/ru-wisper --help")
  end
end
