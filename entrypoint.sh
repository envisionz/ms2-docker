#!/bin/bash

set -e

source "${MS2_SCRIPT_DIR}/tc_common.sh"

# If an environment variable has a _FILE variant, get the contents of that file, otherwise output the non _FILE variant
# usage: get_file_env ENV_FILE ENV
get_file_env()
{
    if [ ! -z "$1" ] && [ -f "$1" ] ; then
        cat "$1"
    else
        printf "%s" "$2"
    fi
}

index_jsonpatch_plugins()
{
    local file_path="$1"
}

int_conf_dir=/internal-config
static_dir=/static
img_asset_dir=/ms2-img-assets
print_dir=/ms2-print-dir

ms2_dir="$MS2_DIR"
ms2_path="/mapstore"
webinf_classes="${ms2_dir}/WEB-INF/classes"
ms2_config_dir="${MS2_DATA_DIR}/configs"

gs_pg_prop="${int_conf_dir}/geostore-datasource-ovr-postgres.properties"
gs_h2_prop="${int_conf_dir}/h2_disk.properties"
gs_user_init="${int_conf_dir}/user_init_list.xml"

orig_local_config="${int_conf_dir}/localConfig.json"
plugin_patch_file="${MS2_PLUGIN_PATCH_DIR}/patch.json"

log_prop="${int_conf_dir}/log4j.properties"

url_path="${MS2_URL_PATH:-$ms2_path}"
proxy_domain="$MS2_PROXY_DOMAIN"
proxy_proto="$MS2_PROXY_PROTO"

# Handle paths first, to account for container restarts
if [ ! -z "$url_path" ]; then
    url_path=$(strip_url_path "$url_path")
fi

set_app_ctx_with_hc "$ms2_dir" "$url_path"

# Setup connector for reverse proxy
if [ ! -z "$proxy_domain" ]; then
    tc_print "Setting up Mapstore2 reverse proxy for ${proxy_domain}..."
    if [ "$proxy_proto" != "http" ] && [ "$proxy_proto" != "https" ]; then
        tc_print "Warning: MS2_PROXY_PROTO not set to http or https. Defaulting to http"
        proxy_proto="http"
    fi
    
    set_connector_proxy "$proxy_domain" "$proxy_proto"
fi

# Setup log4j logging
log_level=${MS2_LOG_LEVEL:-WARN}
cp -f "${log_prop}" "${webinf_classes}/log4j.properties"
sed -i -e "s/INFO/${log_level}/g" "${webinf_classes}/log4j.properties"
printf "%s\n" "org.apache.cxf.common.logging.Slf4jLogger" > "${webinf_classes}/META-INF/cxf/org.apache.cxf.Logger"

if [ -d "$static_dir" ]; then 
    mkdir -p "${ms2_dir}/static" && cp "${static_dir}"/* "${ms2_dir}/static"
fi;

if [ -d "$img_asset_dir" ]; then
    cp -f ${img_asset_dir}/* "${ms2_dir}/dist/web/client/product/assets/img/"
fi

if [ -d "$print_dir" ]; then
    cp -f ${print_dir}/* "${ms2_dir}/printing/"
fi

subtitle_en=$(get_file_env "${MS2_HOME_SUBTITLE_EN_FILE}" "${MS2_HOME_SUBTITLE_EN}")
# todo: make the following more generic for more language support
if [ ! -z "$subtitle_en" ] ; then
    cat "${ms2_dir}/translations/data.en-US.json" | jq --arg st "$subtitle_en" '.messages.home.shortDescription = $st' > ~/data.en-US.json && \
    mv ~/data.en-US.json "${ms2_dir}/translations/data.en-US.json"
fi

home_footer_en=$(get_file_env "${MS2_HOME_FOOTER_EN_FILE}" "${MS2_HOME_FOOTER_EN}")
if [ ! -z "$home_footer_en" ] ; then
    cat "${ms2_dir}/translations/data.en-US.json" | jq --arg ft "$home_footer_en" '.messages.home.footerDescription = $ft' > ~/data.en-US.json && \
    mv ~/data.en-US.json "${ms2_dir}/translations/data.en-US.json"
fi

html_title="${MS2_HTML_TITLE:-"Mapstore HomePage"}"
find "$ms2_dir" "${ms2_dir}/dist" -name "*.html" -exec \
    sed -i -r -e 's|(<title>)MapStore HomePage(</title>)|\1'"$html_title"'\2|g' \
              -e 's|https://cdn\.jslibs\.mapstore2\.geo-solutions\.it/leaflet/favicon\.ico|dist/web/client/product/assets/img/favicon.ico|g' {} \;

if [ -f "$plugin_patch_file" ]; then
    tc_print "Patching localConfig plugins"
    python3 "${MS2_SCRIPT_DIR}/pluginPatch.py" \
        "$orig_local_config" \
        "${ms2_dir}/configs/localConfig.json" \
        "$plugin_patch_file"
fi

if [ "$MS2_USE_SOURCE_MAPS" = "true" ]; then
    cd "${ms2_dir}"
    unzip -o "$MS2_FRONTENT_SRC_MAP_ZIP"
fi

pg_port=${MS2_PG_PORT:-5432}
pg_db=${MS2_PG_DB:-geostore}
pg_schema=${MS2_PG_SCHEMA:-geostore}

pg_user=$(get_file_env "${MS2_PG_USER_FILE}" "${MS2_PG_USER}")

pg_pass=$(get_file_env "${MS2_PG_PASS_FILE}" "${MS2_PG_PASS}")

pg_idle=${MS2_PG_IDLE_MITIGATION:-false}

set_admin_user()
{
    echo "creating admin user..."
    admin_pass=$(get_file_env "${MS2_ADMIN_PASS_FILE}" "${MS2_ADMIN_PASS}")
    xmlstarlet ed -P -L -u "/InitUserList/User/name" -v "${MS2_ADMIN_USER:-admin}" ${gs_user_init}
    xmlstarlet ed -P -L -u "/InitUserList/User/newPassword" -v "${admin_pass:-admin}" ${gs_user_init}
    echo "geostoreInitializer.userListInitFile=file://${gs_user_init}" >> "$1"
}

if [ ! -z "$MS2_PG_HOST" ] && [ ! -z "$pg_user" ] && [ ! -z "$pg_pass" ] ; then
    export PGHOST="$MS2_PG_HOST"
    export PGPORT="$pg_port"
    export PGDATABASE="$pg_db"
    export PGUSER="$pg_user"
    export PGPASSWORD="$pg_pass"

    pg_prop="${MS2_DATA_DIR}/geostore-datasource-ovr.properties"
    cp "$gs_pg_prop" "$pg_prop"
    sed -i -e 's|\(geostoreDataSource.url=\)|\1jdbc:postgresql://'"${MS2_PG_HOST}:${pg_port}"'/'"${pg_db}"'|g' \
        -e 's|\(geostoreDataSource.username=\)|\1'"${pg_user}"'|g' \
        -e 's|\(geostoreDataSource.password=\)|\1'"${pg_pass}"'|g' \
        -e 's|\(geostoreEntityManagerFactory\.jpaPropertyMap\[hibernate\.default_schema\]=\)|\1'"${pg_schema}"'|g' \
        "$pg_prop"
    
    # If requested, add postgres idle connection mitigations
    if [ "$pg_idle" != "false" ]; then
        sed -i -e 's|#geostoreDataSource|geostoreDataSource|g' \
        "$pg_prop"
    fi
    
    until pg_isready; do
        echo "Postgres is unavailable - sleeping"
        sleep 2
    done

    # We can connect to the db. Let's check if the 'geostore' schema exists
    schema_res=`psql -t -c "SELECT schema_name FROM information_schema.schemata WHERE schema_name = '${pg_schema}';"`
    if ! printf "%s" "$schema_res" | grep -q "$pg_schema" ; then
        echo "geostore schema does not exist. creating..."
        psql -c "CREATE SCHEMA ${pg_schema};"
        psql -c "GRANT USAGE ON SCHEMA ${pg_schema} TO ${pg_user};"
        psql -c "GRANT ALL ON SCHEMA ${pg_schema} TO ${pg_user};"
        psql -c "ALTER USER ${pg_user} SET search_path TO ${pg_schema} , public;"

        set_admin_user "$pg_prop"
        sed -i \
            -e 's|\(geostoreEntityManagerFactory\.jpaPropertyMap\[hibernate\.hbm2ddl\.auto\]=\)validate|\1update|g' \
            "$pg_prop"
    fi

    # cleanup
    unset PGHOST
    unset PGPORT
    unset PGDATABASE
    unset PGUSER
    unset PGPASSWORD
else
    echo "Postgres database and/or credentials not supplied"
    echo "Using H2 store at /h2db/db"

    h2_prop="${MS2_DATA_DIR}/geostore-datasource-ovr.properties"
    cp "$gs_h2_prop" "$h2_prop"
    sed -i -e 's,dbc:h2:\./test,dbc:h2:/h2db/db,g' "$h2_prop"
    set_admin_user "$h2_prop"
fi

java_mem_start=${MS2_JAVA_MEM_START:-"256m"} 
java_mem_max=${MS2_JAVA_MEM_MAX:-"512m"} 

mapstore_java_opts="-Xms${java_mem_start} -Xmx${java_mem_max} -Ddatadir.location=${MS2_DATA_DIR}" 
export JAVA_OPTS="${JAVA_OPTS} -Dorg.jboss.logging.provider=log4j ${mapstore_java_opts}"

# Run original tomcat CMD
exec catalina.sh run
