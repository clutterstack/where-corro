## Local development

In the project directory run:
`./corrosion/corrosion agent -c .corrosion/config-local.toml`

In another terminal run `./startlocal.sh`. Running them in separate terminals lets you watch the logs for both.

### Config notes
The Phoenix app will look for an address in the env var `CORRO_API_URL`, which `startlocal.sh` sets. The host and port must match the Corrosion API address in `corrosion/config-local.toml`. i.e.

`CORRO_API_URL="http://localhost:8081/v1"` in `startlocal.sh` matches Corrosion config section

```
[api]
addr = "127.0.0.1:8081"
``` 
