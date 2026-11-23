# 当前发行流程

使用scripts/package-beta.sh，设置SAYTILE_MANDARIN_CANDIDATE=1与现有Developer ID。来源为当前干净HEAD，构建号由packaging/BUILD_NUMBER固定。不得沿用旧no-api固定摘要脚本给新包公证。

公证需要已有notarytool Keychain profile，禁止输出凭据。App提交并Accepted后装订；再生成含已装订App的最终签名DMG、提交DMG并装订，最后验证App/DMG/Gatekeeper、重算SHA-256。没有profile保持BLOCKED，不关Gatekeeper、不删除quarantine、不宣称已发行。
