# Mapstore2-Docker

This is a docker image to easily spin up the (mostly) default [Mapstore2](https://mapstore2.readthedocs.io/en/user_docs/) project, with some basic customization available by way of environment variables.

## Environment Variables

You may customise the container using the following environment variables.

| ENV | Description |
| --- | --- |
| `MS2_ADMIN_USER` | Username for administrator user. Defaults to `admin` |
| `MS2_ADMIN_PASS`, `MS2_ADMIN_PASS_FILE` | Password for administrator user. Defaults to `admin` |
| `MS2_PG_HOST` | PostgreSQL hostname to connect to. |
| `MS2_PG_PORT` | PostgreSQL port. Default `5432` |
| `MS2_PG_DB` | PosrgreSQL database. Default `geostore` |
| `MS2_PG_SCHEMA` | PostgreSQL schema to use. Default `geostore` |
| `MS2_PG_USER`, `MS2_PG_USER_FILE` | PostgreSQL username. |
| `MS2_PG_PASS`, `MS2_PG_PASS_FILE` | PostgreSQL password. |
| `MS2_PG_IDLE_MITIGATION` | Add mitigations for idle postgres connection timeouts |
| `MS2_HOME_SUBTITLE_EN`, `MS2_HOME_SUBTITLE_EN_FILE` | Customise subtitle on Home screen |
| `MS2_HOME_FOOTER_EN`, `MS2_HOME_FOOTER_EN_FILE` | Customise footer on Home screen |
| `MS2_HTML_TITLE` | Customise the HTML title for tab/window |
| `MS2_URL_PATH` | Access Mapstore2 from the specified path. Default is `/mapstore` |
| `MS2_PROXY_DOMAIN` | Set when behind reverse proxy. Example: `my.domain.org` |
| `MS2_PROXY_PROTO` | Is the proxy a TLS terminating proxy? Valid values are `http` or `https` |
| `MS2_JAVA_MEM_START` | Allow setting Java `-Xms` option. Default: `128m` |
| `MS2_JAVA_MEM_MAX` | Allow setting Java `-Xmx` option. Default: `256m` |
| `MS2_LOG_LEVEL` | Log verbosity. Default: `WARN` Allowed: `ALL`, `DEBUG`, `INFO`, `WARN`, `ERROR`, `FATAL`, `OFF` |

The `_FILE` variants listed above take a filepath. The files may be injected via mounts/configs/secrets.

If `MS2_PG_HOST`, `MS2_PG_USER` and `MS2_PG_PASS` are not set, the container falls back to using a Hibernate disk based database file. This file will not be retained unless you mount a volume at `/h2db`.

## Overriding Config Files

If you mount the following files in the container, they will override the default Mapstore2 files:

| Mountpoint | Description |
| --- | --- |
| `/config/localConfig.json` | The main configuration file for Mapstore2.
| `/config/new.json` | The base configuration for creating new maps. |
| `/config/pluginsConfig.json` | Plugin specific configuration file. |

## Adding and Replacing Mapstore Image Assets

You can add or replaces MapStore images stored in the `/dist/web/client/product/assets/img/` directory. Any file mounted in the `/ms2-img-assets` will be copied into the Mapstore image assets directory.

For example, mount an image to `/ms2-img-assets/mapstore-header.jpg` to replace the default jumbotron image.

## Adding and Replacing Mapstore Print Files

You can add or replace the files used for printing, by mounting them to the `/ms2-print-dir` directory. You can replace the banner image (`print_header.png`), north arrow (`Arrow_North_CFCF.svg`), or a modified config file (`config.yaml`).

## Adding Fdditional Files

Additional files can be added to the container, for example logos and map thumbnails. Any files mounted in the `/static` mountpoint will be available.

The files will be available at the `https://your_url/mapstore/static` endpoint.
