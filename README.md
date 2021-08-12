# Mapstore2-Docker

This is a docker image to easily spin up the (mostly) default [Mapstore2](https://mapstore2.readthedocs.io/en/user_docs/) project, with some basic customization available by way of environment variables.

## Environment Variables

You may customise the container using the following environment variables.

| ENV | Description |
| --- | --- |
| `MAPSTORE_ADMIN_USER` | Username for administrator user. Defaults to `admin` |
| `MAPSTORE_ADMIN_PASS`, `MAPSTORE_ADMIN_PASS_FILE` | Password for administrator user. Defaults to `admin` |
| `GS_PG_HOST` | PostgreSQL hostname to connect to. |
| `GS_PG_PORT` | PostgreSQL port. Default `5432` |
| `GS_PG_DB` | PosrgreSQL database. Default `geostore` |
| `GS_PG_SCHEMA` | PostgreSQL schema to use. Default `geostore` |
| `GS_PG_USER`, `GS_PG_USER_FILE` | PostgreSQL username. |
| `GS_PG_PASS`, `GS_PG_PASS_FILE` | PostgreSQL password. |
| `HOME_SUBTITLE_EN`, `HOME_SUBTITLE_EN_FILE` | Customise subtitle on Home screen |
| `HOME_FOOTER_EN`, `HOME_FOOTER_EN_FILE` | Customise footer on Home screen |

The `_FILE` variants listed above take a filepath. The files may be injected via mounts/configs/secrets.

If `GS_PG_HOST`, `GS_PG_USER` and `GS_PG_PASS` are not set, the container falls back to using a Hibernate disk based database file. This file will not be retained unless you mount a volume at `/h2db`.

## Overriding Config Files

If you mount the following files in the container, they will override the default Mapstore2 files:

| Mountpoint | Description |
| --- | --- |
| `/config/localConfig.json` | The main configuration file for Mapstore2.
| `/config/new.json` | The base configuration for creating new maps. |
| `/config/pluginsConfig.json` | Plugin specific configuration file. |

## Adding Fdditional Files

Additional files can be added to the container, for example logos and map thumbnails. Any files mounted in the `/static` mountpoint will be available.

The files will be available at the `https://your_url/mapstore/static` endpoint.
