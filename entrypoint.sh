#!/bin/sh

set -e

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
ms2_dir="${CATALINA_BASE}/webapps/mapstore"
webinf_classes="${ms2_dir}/WEB-INF/classes"

gs_pg_prop="${int_conf_dir}/geostore-datasource-ovr-postgres.properties"
gs_h2_prop="${int_conf_dir}/h2_disk.properties"
gs_user_init="${int_conf_dir}/user_init_list.xml"

local_config="${conf_dir}/localConfig.json"
new_json="${conf_dir}/new.json"
plugins_config="${conf_dir}/pluginsConfig.json"

if [ ! -z "$LDAP_HOST" ] && [ ! -z "$LDAP_BASE_DN" ] && [ ! -z "$LDAP_USER_BASE" ] && [ ! -z "$LDAP_GROUP_BASE" ] ; then
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

    [ -z "$LDAP_PROTOCOL" ] && export LDAP_PROTOCOL="ldap"
    [ -z "$LDAP_PORT" ] && export LDAP_PORT="389"
    [ -z "$LDAP_USER_FILTER" ] && export LDAP_USER_FILTER="(uid={0})"
    [ -z "$LDAP_GROUP_FILTER" ] && export LDAP_GROUP_FILTER="(member={0})"
    [ -z "$LDAP_ROLE_BASE" ] && export LDAP_ROLE_BASE="$LDAP_GROUP_BASE"
    [ -z "$LDAP_ROLE_FILTER" ] && export LDAP_ROLE_FILTER="$LDAP_GROUP_FILTER"
    [ -z "$LDAP_ROLE_PREFIX" ] && export LDAP_ROLE_PREFIX="ROLE_"

    # # Attributes
    [ -z "$LDAP_ATTR_FULL_NAME" ] && export LDAP_ATTR_FULL_NAME="cn"
    [ -z "$LDAP_ATTR_EMAIL" ] && export LDAP_ATTR_EMAIL="mail"

    [ ! -z "$LDAP_NESTED_GROUP_FILTER" ] && xml_edit_attr "//property[@name=enableHierarchicalGroups]/@value" "true"

    export LDAP_BIND_PASS="$(get_file_env ${LDAP_BIND_PASS_FILE} ${LDAP_BIND_PASS})"

    if [ -z "$LDAP_BIND_DN" ] || [ -z "$LDAP_BIND_PASS" ] ; then
        xml_del "//bean[@id=contextSource]/property[@name=userDn]"
        xml_del "//bean[@id=contextSource]/property[@name=password]"
    fi

    # Escape xml characters in LDAP search filters
    export LDAP_USER_FILTER=$(printenv LDAP_USER_FILTER | xmlstarlet esc)
    export LDAP_GROUP_FILTER=$(printenv LDAP_GROUP_FILTER | xmlstarlet esc)
    export LDAP_NESTED_GROUP_FILTER=$(printenv LDAP_NESTED_GROUP_FILTER | xmlstarlet esc)
    export LDAP_ROLE_FILTER=$(printenv LDAP_ROLE_FILTER | xmlstarlet esc)

    # envsubst '${LDAP_HOST} ${LDAP_BASE_DN} ${LDAP_USER_BASE} ${LDAP_GROUP_BASE} ${LDAP_PORT} ${LDAP_USER_FILTER} ${LDAP_GROUP_FILTER} ${LDAP_ROLE_BASE} ${LDAP_ROLE_FILTER} ${LDAP_NESTED_GROUP_FILTER} ${LDAP_BIND_DN} ${LDAP_BIND_PW}' \
    envsubst < "${int_conf_dir}/ldap-geostore-spring-security.xml" > "${ms2_dir}/WEB-INF/classes/geostore-spring-security.xml"
fi

[ -d "$static_dir" ] && mkdir -p "${ms2_dir}/static" && cp "${static_dir}"/* "${ms2_dir}/static"

[ -f "$local_config" ] && cp "$local_config" "${ms2_dir}/localConfig.json"

[ -f "$new_json" ] && cp "$new_json" "${ms2_dir}/new.json"

[ -f "$plugins_config" ] && cp "$plugins_config" "${ms2_dir}/pluginsConfig.json"


HOME_SUBTITLE_EN=$(get_file_env "${HOME_SUBTITLE_EN_FILE}" "${HOME_SUBTITLE_EN}")
# todo: make the following more generic for more language support
if [ ! -z "$HOME_SUBTITLE_EN" ] ; then
    cat "${ms2_dir}/translations/data.en-US.json" | jq --arg st "$HOME_SUBTITLE_EN" '.messages.home.shortDescription = $st' > ~/data.en-US.json && \
    mv ~/data.en-US.json "${ms2_dir}/translations/data.en-US.json"
fi

HOME_FOOTER_EN=$(get_file_env "${HOME_FOOTER_EN_FILE}" "${HOME_FOOTER_EN}")
if [ ! -z "$HOME_FOOTER_EN" ] ; then
    cat "${ms2_dir}/translations/data.en-US.json" | jq --arg ft "$HOME_FOOTER_EN" '.messages.home.footerDescription = $ft' > ~/data.en-US.json && \
    mv ~/data.en-US.json "${ms2_dir}/translations/data.en-US.json"
fi

[ -z "$GS_PG_PORT" ] && GS_PG_PORT=5432

[ -z "$GS_PG_DB" ] && GS_PG_DB=geostore

GS_PG_USER=$(get_file_env "${GS_PG_USER_FILE}" "${GS_PG_USER}")

GS_PG_PASS=$(get_file_env "${GS_PG_PASS_FILE}" "${GS_PG_PASS}")

set_admin_user()
{
    echo "creating admin user..."
    MAPSTORE_ADMIN_PASS=$(get_file_env "${MAPSTORE_ADMIN_PASS_FILE}" "${MAPSTORE_ADMIN_PASS}")

    [ -z MAPSTORE_ADMIN_USER ] && MAPSTORE_ADMIN_USER="admin"
    [ -z MAPSTORE_ADMIN_PASS ] && MAPSTORE_ADMIN_PASS="admin"
    xmlstarlet ed -P -L -u "/InitUserList/User/name" -v "$MAPSTORE_ADMIN_USER" ${gs_user_init}
    xmlstarlet ed -P -L -u "/InitUserList/User/newPassword" -v "$MAPSTORE_ADMIN_PASS" ${gs_user_init}
    echo "geostoreInitializer.userListInitFile=file://${gs_user_init}" >> "$1"
}

if [ ! -z "$GS_PG_HOST" ] && [ ! -z "$GS_PG_USER" ] && [ ! -z "$GS_PG_PASS" ] ; then
    export PGHOST="$GS_PG_HOST"
    export PGPORT="$GS_PG_PORT"
    export PGDATABASE="$GS_PG_DB"
    export PGUSER="$GS_PG_USER"
    export PGPASSWORD="$GS_PG_PASS"

    set -x
    [ -z "$GS_PG_SCHEMA" ] && GS_PG_SCHEMA=geostore

    PG_PROP="${webinf_classes}/geostore-datasource-ovr.properties"
    cp "$gs_pg_prop" "$PG_PROP"
    sed -i -e 's|\(geostoreDataSource.url=\)|\1jdbc:postgresql://'"${GS_PG_HOST}:${GS_PG_PORT}"'/'"${GS_PG_DB}"'|g' \
        -e 's|\(geostoreDataSource.username=\)|\1'"${GS_PG_USER}"'|g' \
        -e 's|\(geostoreDataSource.password=\)|\1'"${GS_PG_PASS}"'|g' \
        -e 's|\(geostoreEntityManagerFactory\.jpaPropertyMap\[hibernate\.default_schema\]=\)|\1'"${GS_PG_SCHEMA}"'|g' \
        "$PG_PROP"
    
    until pg_isready; do
        echo "Postgres is unavailable - sleeping"
        sleep 2
    done

    # We can connect to the db. Let's check if the 'geostore' schema exists
    SCHEMA_RES=`psql -t -c "SELECT schema_name FROM information_schema.schemata WHERE schema_name = '${GS_PG_SCHEMA}';"`
    if ! printf "%s" "$SCHEMA_RES" | grep -q "$GS_PG_SCHEMA" ; then
        echo "geostore schema does not exist. creating..."
        psql -c "CREATE SCHEMA ${GS_PG_SCHEMA};"
        psql -c "GRANT USAGE ON SCHEMA ${GS_PG_SCHEMA} TO ${GS_PG_USER};"
        psql -c "GRANT ALL ON SCHEMA ${GS_PG_SCHEMA} TO ${GS_PG_USER};"
        psql -c "ALTER USER ${GS_PG_USER} SET search_path TO ${GS_PG_SCHEMA} , public;"

        set_admin_user "$PG_PROP"
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

    H2_PROP="${webinf_classes}/geostore-datasource-ovr.properties"
    cp "$gs_h2_prop" "$H2_PROP"
    sed -i -e 's,dbc:h2:\./test,dbc:h2:/h2db/db,g' "$H2_PROP"
    set_admin_user "$H2_PROP"
fi

# Run original tomcat CMD
exec catalina.sh run
