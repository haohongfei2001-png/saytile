# Commands used on the verification Mac

These are the exact package and observation drivers behind the recorded run. Their absolute paths identify the engineer's disposable checkout, synthetic fixture and previously released RC1 package. They are not setup instructions for customers. Test the tagged version in its own checkout and disposable data locations; never point a probe at the installed app's ordinary user database.

- `saytile-noapi7-record.py before|after` fingerprints the tested sources and installer documentation. For the preserved RC1 it reads a bundle metadata field and hashes the executable and previous installer; it does not open the user's database.
- `saytile-noapi7-extract.py` attaches the new DMG read-only, checks its signature, copies the App to a new path and checks the extracted executable and built-in sample. It refuses to overwrite an existing extracted App.
- `saytile-noapi7-package-checks.py` invokes the repository's actual package CLI, upgrade/rollback and idle checks. It requires the frozen SHA in `SAYTILE_EXPECTED_REVISION`.
- `saytile-signed-apple-7.py` runs the extracted executable against the generated Chinese `daily.aiff` in a fresh temporary data directory. The log, the WAV hash and the recording and revision rows are recorded in [the signed-app proof](../apple/signed-app.json); on this run, preparation and a second attempt were unnecessary.
- The separate local [audio persistence recipes](../../local/) use the committed synthetic fixture and real-clock capture. The [protocol pre-run receipt](../protocol/run-before.json) and [native input runner](../input/native-observed-runner.py) identify their own input sets and executables.
- `saytile-noapi7-public.py` downloaded the exact published DMG at an immutable commit and compared the byte count and SHA-256 with the mounted package. `saytile-noapi7-close.py` joins completed, independently recorded observations; it does not execute tests or confer real-cloud verification.
