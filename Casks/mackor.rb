cask "mackor" do
  version "0.3.1"
  sha256 "47f7266a08a446c302c936794ad9133282fa5b14125e0be7212b0a6f9d2ce770"

  url "https://github.com/ASDFGHoney/mackor/releases/download/v#{version}/mackor-#{version}.zip"
  name "mackor"
  desc "Instant, lossless Korean/English switching with Caps Lock"
  homepage "https://github.com/ASDFGHoney/mackor"

  depends_on macos: ">= :ventura"

  app "mackor.app"

  # 설치 직후 실행해서 설정 도우미(접근성 권한 안내)를 띄운다. 이후에는 로그인 항목으로 자동 실행된다.
  postflight do
    system_command "/usr/bin/open", args: ["#{appdir}/mackor.app"]
  end

  # 정상 종료해야 Caps Lock 키 매핑이 원래대로 돌아온다.
  uninstall quit:       "io.mackor.app",
            login_item: "mackor"

  zap script: {
        executable: "/usr/bin/tccutil",
        args:       ["reset", "Accessibility", "io.mackor.app"],
      },
      trash:  "~/Library/Preferences/io.mackor.app.plist"
end
