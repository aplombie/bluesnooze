#!/usr/bin/env python3
"""Generate an own-tap cask from the exact prepared archive. Does not publish it."""
import hashlib
import plistlib
import re
import sys
from pathlib import Path

archive, info, destination = map(Path, sys.argv[1:])
version = plistlib.loads(info.read_bytes())["CFBundleShortVersionString"]
if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,2}", version):
    raise SystemExit("Expected a numeric release version")
checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
content = f'''# Prepared for an own tap. Publish only after the repository rename and release approval.
cask "aplombie-procaine" do
  version "{version}"
  sha256 "{checksum}"

  url "https://github.com/aplombie/procaine/releases/download/v#{{version}}/Procaine.zip"
  name "Procaine"
  desc "Bluetooth sleep protection with simple everyday controls"
  homepage "https://github.com/aplombie/procaine"

  depends_on macos: ">= :ventura"
  app "Procaine.app"

  zap trash: "~/Library/Preferences/io.github.aplombie.procaine.plist"
end
'''
with destination.open("x") as output:
    output.write(content)
