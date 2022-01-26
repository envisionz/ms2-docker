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

conf_dir=/config
int_conf_dir=/internal-config
static_dir=/static
img_asset_dir=/ms2-img-assets
print_dir=/ms2-print-dir

ms2_dir="$MS2_DIR"
ms2_path="/mapstore"
webinf_classes="${ms2_dir}/WEB-INF/classes"
ms2_config_dir="${ms2_dir}/configs"

gs_pg_prop="${int_conf_dir}/geostore-datasource-ovr-postgres.properties"
gs_h2_prop="${int_conf_dir}/h2_disk.properties"
gs_user_init="${int_conf_dir}/user_init_list.xml"
gs_ldap_prop="${int_conf_dir}/ldap.properties"
gs_ldap_xml="${int_conf_dir}/geostore-spring-security-ldap.xml"
ms2_appctx="${int_conf_dir}/applicationContext.xml"
log_prop="${int_conf_dir}/log4j.properties"

local_config="${conf_dir}/localConfig.json"
new_json="${conf_dir}/new.json"
plugins_config="${conf_dir}/pluginsConfig.json"

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

if [ ! -z "$MS2_LDAP_HOST" ] && [ ! -z "$MS2_LDAP_BASE_DN" ] && [ ! -z "$MS2_LDAP_USER_BASE" ] && [ ! -z "$MS2_LDAP_GROUP_BASE" ] ; then
    echo "Configuring LDAP"

    gs_spring_sec="${webinf_classes}/geostore-spring-security.xml"

    ldap_prop="${webinf_classes}/ldap.properties"
    cp "$gs_ldap_prop" "$ldap_prop"

    cp "$gs_ldap_xml" "$gs_spring_sec"

    cp "$ms2_appctx" "${webinf_classes}/applicationContext.xml"

    ldap_bind_pass="${MS2_LDAP_BIND_PASS}"

    ldap_nested_grp_filter=${MS2_LDAP_NESTED_GROUP_FILTER:-"(member={0})"}
    [ ! -z "$ldap_nested_grp_filter" ] && en_hierachical_groups="true"

    # sed -i \
    #     -e "s/\${ldap.proto}/${MS2_LDAP_PROTOCOL:-ldap}/g" \
    #     -e "s/\${ldap.host}/${MS2_LDAP_HOST}/g" \
    #     -e "s/\${ldap.port}/${MS2_LDAP_PORT:-389}/g" \
    #     -e "s/\${ldap.root}/${MS2_LDAP_BASE_DN}/g" \
    #     -e "s/\${ldap.userDn}/${MS2_LDAP_BIND_USER}/g" \
    #     -e "s/\${ldap.password}/${ldap_bind_pass}/g" \
    #     -e "s/\${ldap.userBase}/${MS2_LDAP_USER_BASE}/g" \
    #     -e "s/\${ldap.groupBase}/${MS2_LDAP_GROUP_BASE}/g" \
    #     -e "s/\${ldap.roleBase}/${MS2_LDAP_ROLE_BASE:-$MS2_LDAP_GROUP_BASE}/g" \
    #     -e "s/\${ldap.userFilter}/$(printf %s ${MS2_LDAP_USER_FILTER:-"(uid={0})"} | xmlstarlet esc)/g" \
    #     -e "s/\${ldap.groupFilter}/$(printf %s ${MS2_LDAP_GROUP_FILTER:-"(member={0})"} | xmlstarlet esc)/g" \
    #     -e "s/\${ldap.roleFilter}/$(printf %s ${MS2_LDAP_ROLE_FILTER:-$MS2_LDAP_GROUP_FILTER} | xmlstarlet esc)/g" \
    #     -e "s/\${ldap.nestedGroupFilter}/$(printf %s ${MS2_LDAP_NESTED_GROUP_FILTER:-"(member={0})"} | xmlstarlet esc)/g" \
    #     -e "s/\${ldap.attrMail}/${MS2_LDAP_ATTR_EMAIL:-mail}/g" \
    #     -e "s/\${ldap.attrFN}/${MS2_LDAP_ATTR_FULL_NAME:-cn}/g" \
    #     -e "s/\${ldap.attrDescription}/${MS2_LDAP_ATTR_DESCRIPTION:-description}/g" \
    #     -e "s/\${ldap.hierachicalGroups}/${en_hierachical_groups:-false}/g" \
    #     -e "s/\${ldap.memberPattern}//g" \
    #     "$gs_spring_sec"

    sed -i \
        -e "s/ldap.proto=/ldap.proto=${MS2_LDAP_PROTOCOL:-ldap}/g" \
        -e "s/ldap.host=/ldap.host=${MS2_LDAP_HOST}/g" \
        -e "s/ldap.port=/ldap.port=${MS2_LDAP_PORT:-389}/g" \
        -e "s/ldap.root=/ldap.root=${MS2_LDAP_BASE_DN}/g" \
        -e "s/ldap.userDn=/ldap.userDn=${MS2_LDAP_BIND_USER}/g" \
        -e "s/ldap.password=/ldap.password=${ldap_bind_pass}/g" \
        -e "s/ldap.userBase=/ldap.userBase=${MS2_LDAP_USER_BASE}/g" \
        -e "s/ldap.groupBase=/ldap.groupBase=${MS2_LDAP_GROUP_BASE}/g" \
        -e "s/ldap.roleBase=/ldap.roleBase=${MS2_LDAP_ROLE_BASE:-$MS2_LDAP_GROUP_BASE}/g" \
        -e "s/ldap.userFilter=/ldap.userFilter=${MS2_LDAP_USER_FILTER:-"(uid={0})"}/g" \
        -e "s/ldap.groupFilter=/ldap.groupFilter=${MS2_LDAP_GROUP_FILTER:-"(member={0})"}/g" \
        -e "s/ldap.roleFilter=/ldap.roleFilter=${MS2_LDAP_ROLE_FILTER:-$MS2_LDAP_GROUP_FILTER}/g" \
        -e "s/ldap.nestedGroupFilter=/ldap.nestedGroupFilter=${MS2_LDAP_NESTED_GROUP_FILTER:-"(member={0})"}/g" \
        -e "s/ldap.attrMail=/ldap.attrMail=${MS2_LDAP_ATTR_EMAIL:-mail}/g" \
        -e "s/ldap.attrFN=/ldap.attrFN=${MS2_LDAP_ATTR_FULL_NAME:-cn}/g" \
        -e "s/ldap.attrDescription=/ldap.attrDescription=${MS2_LDAP_ATTR_DESCRIPTION:-description}/g" \
        -e "s/ldap.hierachicalGroups=/ldap.hierachicalGroups=${en_hierachical_groups:-false}/g" \
        "$ldap_prop"
fi

[ -d "$static_dir" ] && mkdir -p "${ms2_dir}/static" && cp "${static_dir}"/* "${ms2_dir}/static"

[ -f "$local_config" ] && cp "$local_config" "${ms2_config_dir}/localConfig.json"

[ -f "$new_json" ] && cp "$new_json" "${ms2_config_dir}/new.json"

[ -f "$plugins_config" ] && cp "$plugins_config" "${ms2_config_dir}/pluginsConfig.json"

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

    h2_prop="${webinf_classes}/geostore-datasource-ovr.properties"
    cp "$gs_h2_prop" "$h2_prop"
    sed -i -e 's,dbc:h2:\./test,dbc:h2:/h2db/db,g' "$h2_prop"
    set_admin_user "$h2_prop"
fi

java_mem_start=${MS2_JAVA_MEM_START:-"128m"} 
java_mem_max=${MS2_JAVA_MEM_MAX:-"256m"} 

mapstore_java_opts="-Xms${java_mem_start} -Xmx${java_mem_max} -Ddatadir.location=${MS2_DATA_DIR}"
export JAVA_OPTS="${JAVA_OPTS} ${mapstore_java_opts}"

# Run original tomcat CMD
exec catalina.sh run
