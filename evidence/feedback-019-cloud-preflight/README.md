# Saytile 0.19 feedback delivery checkpoint

The macOS client is build 500 at `412d008be30471abf7cf89e99ee7d4c10ae6cb92`. The reviewed two-Worker service is `6fba674ab4db536efea2090c4e482db73a3b949e`. These checks extend the [native client acceptance](../feedback-019-final/README.md).

| Check on 2026-11-16 (UTC) | Result | Observation |
|---|---|---|
| macOS URLSession reachability | PASS | The feedback endpoint returned HTTP 401 to an anonymous HEAD at the original URL. |
| Deployed receiver accepts Saytile's structured product field | FAIL | For the same expired synthetic envelope, the legacy form reached the age check (422 `submission_age`). Adding only `product=saytile` yielded 422 `schema`. A subsequent GET with the same ID and capability returned 404 `not_found`. |
| Reviewed Worker bundles and additive migration | PASS locally | Both Workers bundled with Wrangler 4.162.0. The local D1 migration preserved all 14 fields of a synthetic legacy record and both quota rows. All three supported product labels passed and an unknown value was rejected. [Rehearsal receipt](wrangler-rehearsal.json) |
| Single synthetic report, restart and reply loss | PASS locally | The production Swift feedback engine froze the bytes and stored the report. The offline test exercised separate processes, refused a second POST intent and resumed by ID. |
| Worker deployment | BLOCKED | Wrangler reported no authenticated account or named profile. Provider authorization from the existing account holder is pending. |
| Saytile receipt and matching private Issue | NOT_RUN | The prepared valid report has zero submission attempts. |

The [read-only outcome of the expired fixture check](receiver-results.json) is specific to the public Receiver. It does not identify the deployed Delivery version. The [check source](ReceiverSchemaCheck.swift) sets creation time to the Unix epoch and uses the same ID, capability and contents for both payloads. It sends no personal data.

## Continue after authentication

Use the dedicated Wrangler profile `saytile-feedback` and the service deployment sequence in Riftlet PR #104. Confirm the existing account, deployed versions, D1 binding and schema before applying the additive migration. The target is the private repository `haohongfei2001-png/Riftlet-Feedback`.

For the prepared local outbox, use `scripts/accept-saytile-feedback.sh submit /private/tmp/saytile-feedback-acceptance-019-500` once after deploying. Use `status` with the same path to query the original ID. Verify that its private Issue has the exact marker and label `product:saytile`. A receiver receipt alone confirms only receipt. This probe runs the production engine and HTTPS transport in a native CLI fixture. The signed App's settings interaction has separate mock-transport evidence.

If the temporary outbox is missing, reconcile the known ID remotely before preparing a replacement. The capability stays in its isolated local directory.
