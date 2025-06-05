# corro-sandwiches-ex

An Elixir client/demo for Corrosion

## Run locally
Build or get a Corrosion binary and copy it to the project dir
Edit and run `startlocal.sh`, which sets some env vars and runs `iex -S mix phx.server`.

## Deploy to Fly.io
fly apps create
put the new app name into fly.toml so you don't have to keep using -a
fly secrets set SECRET_KEY_BASE=$(mix phx.gen.secret 64)
fly volumes create corro_data -y -s 1 # (can skip this; fly deploy will do it)
fly ips allocate-v4 --shared
fly ips allocate-v6
<!-- If using a separate app running on Fly.io for corrosion -->
fly deploy -a where-corro-sep -c fly-separate.toml --dockerfile Dockerfile-separate

<!-- To use corrosion built into the Machine -->
<!-- Make sure to copy an up-to-date Corrosion binary to the project dir -->
fly deploy -a sandwich-builtin --dockerfile Dockerfile-allinone


## What else 

* CORRO_BUILTIN and FLY_CORROSION_APP are used to determine whether to use local corrosion or a separate app
* right now it exits when corrosion app isn't reachable. THis is for corrosion testing, so I can see the logs


## `CORRO_BUILTIN`

The `CORRO_BUILTIN` env var (set, by `fly.toml` or the `startlocal.sh` script) is used:

To set `corro_api_url`, `fly_corrosion_app`, and `corro_builtin` in runtime.exs 

`corro_builtin` (app env) is used
* in CorroCalls: ` WhereCorro.FlyDnsReq.get_corro_instance()`
* in FriendFinder, to decide whether to run `check_corro_regions` to update regions and the nearest corrosion get_corro_instance
* in StartupChecks to confirm that `FLY_CORROSION_APP` is set (because I was making that mistake when switching between builtin and separate I guess)
* in a similar check in MessagePropagator that Claude created.

## `CORRO_API_URL`
Set by startlocal.sh or fly.toml. Either a local addr or one on a separate Corrosion app.
  * used to set app env `corro_api_url`

As app env `corro_api_url`:
  * in StartupChecks, to check that it's set.
  * used to compose corrosion request urls by tacking `transactions` or whatever to it.
  * used to build watch url in CorroWatch, by adding `/subscriptions` 


## `FLY_CORROSION_APP`
Set in startlocal.sh. Used when Corrosion isn't on the same app as the client.

* was used in entrypoint script to set bootstrap addr in corrosion config (separate mode)
* used in runtime.exs to set `fly_corrosion_app` app env and `corro_api_url` app env (separate mode)

### as `fly_corrosion_app` app env

* Used in FlyDnsReq which is all about finding the addresses of Corrosion Machines that aren't in the same app.
* Used in `check_corro_regions` in FriendFinder.
* Used in StartupChecks to check that `FLY_CORROSION_APP` has been set if `corro_builtin != "1"`.

## Other app env settings
 
* fly_region: System.get_env("FLY_REGION"),
* fly_vm_id: System.get_env("FLY_MACHINE_ID"),
* fly_app_name: System.get_env("FLY_APP_NAME"),
* fly_private_ip: System.get_env("FLY_PRIVATE_IP")
