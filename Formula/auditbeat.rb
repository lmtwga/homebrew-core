class Auditbeat < Formula
  desc "Lightweight Shipper for Audit Data"
  homepage "https://www.elastic.co/products/beats/auditbeat"
  url "https://github.com/elastic/beats/archive/v6.2.2.tar.gz"
  sha256 "0866c3e26fcbd55f191e746b3bf925b450badd13fb72ea9f712481559932c878"
  head "https://github.com/elastic/beats.git"

  bottle do
    cellar :any_skip_relocation
    rebuild 1
    sha256 "0f8cc0318b2a3ed92186aacd0983a7ad798dde49e023e4b9183c8cfcab3f4bc1" => :high_sierra
    sha256 "1c1b25d013e44a86f84f4715a0f51b1c96ed92f68c3183a7ede62abf0defa3af" => :sierra
    sha256 "d4d78782427d7485eb18f3deabd72d676ac307e55745f1a209331d44636546b3" => :el_capitan
  end

  depends_on "go" => :build

  # Patch required to build against go 1.10.
  # May be removed once upstream beats project fully supports go 1.10.
  patch do
    url "https://raw.githubusercontent.com/Homebrew/formula-patches/1ddc0e6/auditbeat/go1.10.diff"
    sha256 "cf0988ba5ff5cc8bd7502671f08ea282b19720be42bea2aaf5c236b29a01a24f"
  end

  resource "virtualenv" do
    url "https://files.pythonhosted.org/packages/d4/0c/9840c08189e030873387a73b90ada981885010dd9aea134d6de30cd24cb8/virtualenv-15.1.0.tar.gz"
    sha256 "02f8102c2436bb03b3ee6dede1919d1dac8a427541652e5ec95171ec8adbc93a"
  end

  def install
    ENV["GOPATH"] = buildpath
    (buildpath/"src/github.com/elastic/beats").install buildpath.children

    ENV.prepend_create_path "PYTHONPATH", buildpath/"vendor/lib/python2.7/site-packages"

    resource("virtualenv").stage do
      system "python", *Language::Python.setup_install_args(buildpath/"vendor")
    end

    ENV.prepend_path "PATH", buildpath/"vendor/bin"

    cd "src/github.com/elastic/beats/auditbeat" do
      system "make"
      # prevent downloading binary wheels during python setup
      system "make", "PIP_INSTALL_COMMANDS=--no-binary :all", "python-env"
      system "make", "DEV_OS=darwin", "update"
      (libexec/"bin").install "auditbeat"
      libexec.install "_meta/kibana"

      (etc/"auditbeat").install Dir["auditbeat*.yml", "fields.yml"]
      prefix.install_metafiles
    end

    (bin/"auditbeat").write <<~EOS
      #!/bin/sh
        exec #{libexec}/bin/auditbeat \
        -path.config #{etc}/auditbeat \
        -path.data #{var}/lib/auditbeat \
        -path.home #{libexec} \
        -path.logs #{var}/log/auditbeat \
        "$@"
    EOS
  end

  def post_install
    (var/"lib/auditbeat").mkpath
    (var/"log/auditbeat").mkpath
  end

  plist_options :manual => "auditbeat"

  def plist; <<~EOS
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
      <dict>
        <key>Label</key>
        <string>#{plist_name}</string>
        <key>Program</key>
        <string>#{opt_bin}/auditbeat</string>
        <key>RunAtLoad</key>
        <true/>
      </dict>
    </plist>
  EOS
  end

  test do
    (testpath/"files").mkpath
    (testpath/"config/auditbeat.yml").write <<~EOS
      auditbeat.modules:
      - module: file_integrity
        paths:
          - #{testpath}/files
      output.file:
        path: "#{testpath}/auditbeat"
        filename: auditbeat
    EOS
    pid = fork do
      exec "#{bin}/auditbeat", "-path.config", testpath/"config", "-path.data", testpath/"data"
    end
    sleep 5

    begin
      touch testpath/"files/touch"
      sleep 30
      s = IO.readlines(testpath/"auditbeat/auditbeat").last(1)[0]
      assert_match "\"action\":\[\"created\"\]", s
      realdirpath = File.realdirpath(testpath)
      assert_match "\"path\":\"#{realdirpath}/files/touch\"", s
    ensure
      Process.kill "SIGINT", pid
      Process.wait pid
    end
  end
end
