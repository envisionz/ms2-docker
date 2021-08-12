FROM tomcat:9-jdk11-openjdk-buster

# Tomcat specific options
ENV CATALINA_BASE "$CATALINA_HOME"
ENV JAVA_OPTS="${JAVA_OPTS}  -Xms512m -Xmx512m"

ARG MS2_TAG=v2021.01.03
ARG GEOSTORE_VERS=v1.6.0

RUN apt-get update && apt-get install -y postgresql-client jq xmlstarlet gettext && apt-get clean

# Download and extract Mapstore2 WAR files
RUN cd ${CATALINA_BASE}/webapps && \
    wget https://github.com/geosolutions-it/MapStore2/releases/download/${MS2_TAG}/mapstore.war && \
    wget https://github.com/geosolutions-it/MapStore2/releases/download/${MS2_TAG}/mapstore-printing.zip && \
    mkdir ./mapstore && \
    cd ./mapstore && jar -xvf ../mapstore.war && \
    unzip ../mapstore-printing.zip && cd .. && \
    rm mapstore.war mapstore-printing.zip

# Dowonload Geostore and extract sql scripts
RUN git clone https://github.com/geosolutions-it/geostore.git -b ${GEOSTORE_VERS} && \
    mkdir -p /internal-config/sql && cp -R geostore/doc/sql/. /internal-config/sql && rm -rf geostore

# Copy files required for customization
COPY ./config/ /internal-config/
# Set variable to better handle terminal commands
ENV TERM xterm

RUN groupadd -r tomcat-docker && useradd --no-log-init -m -r -g tomcat-docker tomcat-docker
RUN chown -R tomcat-docker "$CATALINA_HOME"
RUN chown tomcat-docker /internal-config/user_init_list.xml
RUN mkdir -p /h2db && chown tomcat-docker /h2db

COPY ./entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER tomcat-docker

ENTRYPOINT [ "/entrypoint.sh" ]

EXPOSE 8080
