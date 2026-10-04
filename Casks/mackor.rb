cask "mackor" do
  version "0.4.1"
  sha256 "b550024aa00807875f51d7ac1080afc67085088266df75a4c8361c7dc972fd2b"

  url "https://github.com/ASDFGHoney/mackor/releases/download/v#{version}/mackor-#{version}.zip"
  name "mackor"
  desc "Instant, lossless Korean/English switching with Caps Lock"
  homepage "https://github.com/ASDFGHoney/mackor"

  depends_on macos: :ventura

  app "mackor.app"

  # 정상 종료해야 Caps Lock 키 매핑이 원래대로 돌아온다.
  uninstall quit:       "io.mackor.app",
            login_item: "mackor"

  zap script: {
        executable: "/usr/bin/tccutil",
        args:       ["reset", "Accessibility", "io.mackor.app"],
      },
      trash:  "~/Library/Preferences/io.mackor.app.plist"

  # Homebrew 7은 설치 단계에서 앱 실행을 막으므로(샌드박스의 lsopen 거부) 첫 실행은 사용자에게 맡긴다.
  caveats <<~EOS
    mackor를 한 번 실행해 설정 도우미를 따라 접근성 권한을 허용하세요:
      open -a mackor
    처음 실행할 때 로그인 항목에 등록되어, 이후에는 로그인하면 자동으로 실행됩니다.
  EOS
end
