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
ms2_dir="${CATALINA_HOME}/webapps/mapstore"
ms2_path="/mapstore"
webinf_classes="${ms2_dir}/WEB-INF/classes"

gs_pg_prop="${int_conf_dir}/geostore-datasource-ovr-postgres.properties"
gs_h2_prop="${int_conf_dir}/h2_disk.properties"
gs_user_init="${int_conf_dir}/user_init_list.xml"

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

if [ -z "$url_path" ]; then
    ms2_dir=$(set_app_path "$ms2_path")
    tc_print "Mapstore2 will be available at '/' path"
else
    ms2_dir=$(set_app_path "$ms2_path" "$url_path")
    tc_print "Mapstore2 will be available at '/${url_path}' path"
fi

# Setup connector for reverse proxy
if [ ! -z "$proxy_domain" ]; then
    tc_print "Setting up Mapstore2 reverse proxy for ${proxy_domain}..."
    if [ "$proxy_proto" != "http" ] && [ "$proxy_proto" != "https" ]; then
        tc_print "Warning: MS2_PROXY_PROTO not set to http or https. Defaulting to http"
        proxy_proto="http"
    fi
    
    set_connector_proxy "$proxy_domain" "$proxy_proto"
fi

# Setup tomcat healthcheck
set_healthcheck "$ms2_dir"

if [ ! -z "$MS2_LDAP_HOST" ] && [ ! -z "$MS2_LDAP_BASE_DN" ] && [ ! -z "$MS2_LDAP_USER_BASE" ] && [ ! -z "$MS2_LDAP_GROUP_BASE" ] ; then
    echo "Configuring LDAP"
    # "${ms2_dir}/WEB-INF/classes/geostore-spring-security.xml"
    xml_del() 
    {
        xmlstarlet ed -P -L -d "$1" "${int_conf_dir}/ldap-geostore-spring-security.xml"
    }
    xml_edit_attr()
    {
        xmlstarlet ed -P -L -u "$1" -v "$2" "${int_conf_dir}/ldap-geostore-spring-security.xml"
    }

    [ -z "$MS2_LDAP_PROTOCOL" ] && export MS2_LDAP_PROTOCOL="ldap"
    [ -z "$MS2_LDAP_PORT" ] && export MS2_LDAP_PORT="389"
    [ -z "$MS2_LDAP_USER_FILTER" ] && export MS2_LDAP_USER_FILTER="(uid={0})"
    [ -z "$MS2_LDAP_GROUP_FILTER" ] && export MS2_LDAP_GROUP_FILTER="(member={0})"
    [ -z "$MS2_LDAP_ROLE_BASE" ] && export MS2_LDAP_ROLE_BASE="$MS2_"
    [ -z "$MS2_LDAP_ROLE_FILTER" ] && export MS2_LDAP_ROLE_FILTER="$MS2_LDAP_GROUP_FILTER"
    [ -z "$MS2_LDAP_ROLE_PREFIX" ] && export MS2_LDAP_ROLE_PREFIX="ROLE_"

    # # Attributes
    [ -z "$MS2_LDAP_ATTR_FULL_NAME" ] && export MS2_LDAP_ATTR_FULL_NAME="cn"
    [ -z "$MS2_LDAP_ATTR_EMAIL" ] && export MS2_LDAP_ATTR_EMAIL="mail"

    [ ! -z "$MS2_LDAP_NESTED_GROUP_FILTER" ] && xml_edit_attr "//property[@name=enableHierarchicalGroups]/@value" "true"

    export MS2_LDAP_BIND_PASS="$(get_file_env ${MS2_LDAP_BIND_PASS_FILE} ${MS2_LDAP_BIND_PASS})"

    if [ -z "$MS2_LDAP_BIND_DN" ] || [ -z "$MS2_LDAP_BIND_PASS" ] ; then
        xml_del "//bean[@id=contextSource]/property[@name=userDn]"
        xml_del "//bean[@id=contextSource]/property[@name=password]"
    fi

    # Escape xml characters in LDAP search filters
    export MS2_LDAP_USER_FILTER=$(printenv MS2_LDAP_USER_FILTER | xmlstarlet esc)
    export MS2_LDAP_GROUP_FILTER=$(printenv MS2_LDAP_GROUP_FILTER | xmlstarlet esc)
    export MS2_LDAP_NESTED_GROUP_FILTER=$(printenv MS2_LDAP_NESTED_GROUP_FILTER | xmlstarlet esc)
    export MS2_LDAP_ROLE_FILTER=$(printenv MS2_LDAP_ROLE_FILTER | xmlstarlet esc)

    # envsubst '${MS2_LDAP_HOST} ${MS2_} ${MS2_} ${MS2_} ${MS2_LDAP_PORT} ${MS2_LDAP_USER_FILTER} ${MS2_LDAP_GROUP_FILTER} ${MS2_LDAP_ROLE_BASE} ${MS2_LDAP_ROLE_FILTER} ${MS2_LDAP_NESTED_GROUP_FILTER} ${MS2_LDAP_BIND_DN} ${LDAP_BIND_PW}' \
    envsubst < "${int_conf_dir}/ldap-geostore-spring-security.xml" > "${ms2_dir}/WEB-INF/classes/geostore-spring-security.xml"
fi

[ -d "$static_dir" ] && mkdir -p "${ms2_dir}/static" && cp "${static_dir}"/* "${ms2_dir}/static"

[ -f "$local_config" ] && cp "$local_config" "${ms2_dir}/localConfig.json"

[ -f "$new_json" ] && cp "$new_json" "${ms2_dir}/new.json"

[ -f "$plugins_config" ] && cp "$plugins_config" "${ms2_dir}/pluginsConfig.json"


MS2_HOME_SUBTITLE_EN=$(get_file_env "${MS2_HOME_SUBTITLE_EN_FILE}" "${MS2_HOME_SUBTITLE_EN}")
# todo: make the following more generic for more language support
if [ ! -z "$MS2_HOME_SUBTITLE_EN" ] ; then
    cat "${ms2_dir}/translations/data.en-US.json" | jq --arg st "$MS2_HOME_SUBTITLE_EN" '.messages.home.shortDescription = $st' > ~/data.en-US.json && \
    mv ~/data.en-US.json "${ms2_dir}/translations/data.en-US.json"
fi

MS2_HOME_FOOTER_EN=$(get_file_env "${MS2_HOME_FOOTER_EN_FILE}" "${MS2_HOME_FOOTER_EN}")
if [ ! -z "$MS2_HOME_FOOTER_EN" ] ; then
    cat "${ms2_dir}/translations/data.en-US.json" | jq --arg ft "$MS2_HOME_FOOTER_EN" '.messages.home.footerDescription = $ft' > ~/data.en-US.json && \
    mv ~/data.en-US.json "${ms2_dir}/translations/data.en-US.json"
fi

[ -z "$MS2_PG_PORT" ] && MS2_PG_PORT=5432

[ -z "$MS2_PG_DB" ] && MS2_PG_DB=geostore

MS2_PG_USER=$(get_file_env "${MS2_PG_USER_FILE}" "${MS2_PG_USER}")

MS2_PG_PASS=$(get_file_env "${MS2_PG_PASS_FILE}" "${MS2_PG_PASS}")

set_admin_user()
{
    echo "creating admin user..."
    MS2_ADMIN_PASS=$(get_file_env "${MS2_ADMIN_PASS_FILE}" "${MS2_ADMIN_PASS}")

    [ -z MS2_ADMIN_USER ] && MS2_ADMIN_USER="admin"
    [ -z MS2_ADMIN_PASS ] && MS2_ADMIN_PASS="admin"
    xmlstarlet ed -P -L -u "/InitUserList/User/name" -v "$MS2_ADMIN_USER" ${gs_user_init}
    xmlstarlet ed -P -L -u "/InitUserList/User/newPassword" -v "$MS2_ADMIN_PASS" ${gs_user_init}
    echo "geostoreInitializer.userListInitFile=file://${gs_user_init}" >> "$1"
}

if [ ! -z "$MS2_PG_HOST" ] && [ ! -z "$MS2_PG_USER" ] && [ ! -z "$MS2_PG_PASS" ] ; then
    export PGHOST="$MS2_PG_HOST"
    export PGPORT="$MS2_PG_PORT"
    export PGDATABASE="$MS2_PG_DB"
    export PGUSER="$MS2_PG_USER"
    export PGPASSWORD="$MS2_PG_PASS"

    set -x
    [ -z "$MS2_PG_SCHEMA" ] && MS2_PG_SCHEMA=geostore

    pg_prop="${webinf_classes}/geostore-datasource-ovr.properties"
    cp "$gs_pg_prop" "$pg_prop"
    sed -i -e 's|\(geostoreDataSource.url=\)|\1jdbc:postgresql://'"${MS2_PG_HOST}:${MS2_PG_PORT}"'/'"${MS2_PG_DB}"'|g' \
        -e 's|\(geostoreDataSource.username=\)|\1'"${MS2_PG_USER}"'|g' \
        -e 's|\(geostoreDataSource.password=\)|\1'"${MS2_PG_PASS}"'|g' \
        -e 's|\(geostoreEntityManagerFactory\.jpaPropertyMap\[hibernate\.default_schema\]=\)|\1'"${MS2_PG_SCHEMA}"'|g' \
        "$pg_prop"
    
    until pg_isready; do
        echo "Postgres is unavailable - sleeping"
        sleep 2
    done

    # We can connect to the db. Let's check if the 'geostore' schema exists
    schema_res=`psql -t -c "SELECT schema_name FROM information_schema.schemata WHERE schema_name = '${MS2_PG_SCHEMA}';"`
    if ! printf "%s" "$schema_res" | grep -q "$MS2_PG_SCHEMA" ; then
        echo "geostore schema does not exist. creating..."
        psql -c "CREATE SCHEMA ${MS2_PG_SCHEMA};"
        psql -c "GRANT USAGE ON SCHEMA ${MS2_PG_SCHEMA} TO ${MS2_PG_USER};"
        psql -c "GRANT ALL ON SCHEMA ${MS2_PG_SCHEMA} TO ${MS2_PG_USER};"
        psql -c "ALTER USER ${MS2_PG_USER} SET search_path TO ${MS2_PG_SCHEMA} , public;"

        set_admin_user "$pg_prop"
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

# Run original tomcat CMD
exec catalina.sh run
