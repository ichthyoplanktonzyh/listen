# Local Model Test Credentials

These instructions apply to model tests run on this machine.

- Never print, log, commit, or persist an API key.
- Normal tests and CI must not require a real credential.
- Run paid/live model tests only when the task explicitly authorizes them.
- DeepSeek tests read `DEEPSEEK_API_KEY` from the test process.
- Optional overrides are `DEEPSEEK_BASE_URL` and `DEEPSEEK_MODEL`.
- This machine may keep an older DeepSeek credential in `~/.zshrc` under the
  commented variables `ANTHROPIC_API_KEY` or `ANTHROPIC_AUTH_TOKEN`.
- If `DEEPSEEK_API_KEY` is not exported, read one of those local values into a
  temporary shell variable and pass it only to the test process. Do not
  uncomment or modify `~/.zshrc`.
- When inspecting local configuration, show only whether the credential exists
  and its variable name/path. Always redact the value.
- Unset any temporary shell variable after the command finishes.

On this machine, resolve the commented local credential and pass it only to
the live DeepSeek smoke-test process with:

```bash
deepseek_test_key=$(sed -n 's/^# export ANTHROPIC_API_KEY=//p' "$HOME/.zshrc" | head -n 1)
if [ -z "$deepseek_test_key" ]; then
  deepseek_test_key=$(sed -n 's/^# export ANTHROPIC_AUTH_TOKEN=//p' "$HOME/.zshrc" | head -n 1)
fi
deepseek_test_key=${deepseek_test_key#\"}
deepseek_test_key=${deepseek_test_key%\"}
DEEPSEEK_API_KEY="$deepseek_test_key" \
  cargo test -p llm-provider --test deepseek_integration -- --ignored --nocapture
unset deepseek_test_key
```

The live test is ignored by default so routine `cargo test` and CI cannot spend
model credit accidentally.
