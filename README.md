version: '3.9'



services:

  fluentd:

    user: root

    image: enocean/iotconnector_fluentd:latest

    volumes:

      - /var/lib/docker/containers:/var/lib/docker/containers

      - ./logs:/outputs/

    logging:

      driver: local

    environment:

      - ES_HOST=elasticsearch

      - ES_PORT=9200

      - ES_USER_NAME=elastic

      - ES_PASSWORD=changeme

      - ES_PROTOCOL=http



  elasticsearch:

    image: docker.elastic.co/elasticsearch/elasticsearch:7.10.1

    environment:

      - discovery.type=single-node

      - xpack.security.enabled=true

      - ELASTIC_PASSWORD=changeme

    volumes:

      - elasticsearch-data:/usr/share/elasticsearch/data

    ports:

      - "9200:9200"



  kibana:

    image: docker.elastic.co/kibana/kibana:7.10.1

    depends_on:

      - elasticsearch

    environment:

      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200

      - ELASTICSEARCH_USERNAME=elastic

      - ELASTICSEARCH_PASSWORD=changeme

    ports:

      - "5601:5601"



  redis:

    image: redis:6.2

    command: redis-server --protected-mode no

    ports:

      - "6379:6379"

    restart: always

    volumes:

      - redis-volume:/data

    logging:

      driver: json-file

      options:

        max-size: "100m"

        max-file: "2"



  ingress:

    image: enocean/iotconnector_ingress:latest

    restart: always

    ports:

      - "7070:7070"

    environment:

      - REDIS_URL=redis

      - RABBITMQ_HOST=rabbitmq

      - IOT_LICENSE_KEY= #enter license here

      - IOT_AUTH_CALLBACK= #enter URL here

      - IOT_GATEWAY_USERNAME= #enter username here

      - IOT_GATEWAY_PASSWORD= #enter password here

    depends_on:

      - redis

      - rabbitmq

    logging:
      driver: json-file

      options:

        max-size: "100m"

        max-file: "2"



  api:

    image: enocean/iotconnector_api:latest

    ports:

      - "1887:1887"

    restart: always

    environment:

      - REDIS_URL=redis://redis:6379/0

      - LICENSE_KEY=

      - DJANGO_SETTINGS_MODULE=eiotc_api.settings.prod

    volumes:

      - ./logs:/var/log/enocean/eiotc

    depends_on:

      - redis

    logging:

      driver: json-file

      options:

        max-size: "100m"

        max-file: "2"



  engine:

    image: enocean/iotconnector_engine:latest

    restart: always

    environment:

      - REDIS_URL=redis

      - RABBITMQ_HOST=rabbitmq

      - IOT_LICENSE_KEY= #enter license here

      - MQTT_CONNSTRING=mqtt:1883

      - IOT_ENABLE_MQTT=1

      - IOT_MQTT_CLIENT_ID=iotc_test_instance_1

      - INGRESS_HOST=ingress

      - INGRESS_PORT=7070

      - INGRESS_USERNAME=user1

      - INGRESS_PASS=pass

      - API_URL=http://api:1887/api/v2

    depends_on:

      - redis

      - rabbitmq

    logging:

      driver: json-file

      options:

        max-size: "100m"

        max-file: "2"



  integration:

    image: enocean/iotconnector_integration:latest

    environment:

      - REDIS_URL=redis

      - RABBITMQ_HOST=rabbitmq

      - IOT_ENABLE_MQTT=1

      - MQTT_CONNSTRING=mqtt:1883

      - SENSOR_STATS_INTERVAL=600

      - GATEWAY_STATS_INTERVAL=600

    depends_on:

      - engine

      - redis

      - rabbitmq

    logging:

      driver: json-file

      options:

        max-size: "100m"

        max-file: "2"



  proxy:

    image: enocean/proxy:local

    restart: always

    ports:

      - "443:443"

      - "80:80"

      - "8080:8080"

    secrets:

      - source: secret-proxy-certificate

        target: /etc/nginx/certs/cert.crt

      - source: secret-proxy-key

        target: /etc/nginx/certs/cert.key

    environment:

      - BASIC_AUTH_USERNAME=admin

      - BASIC_AUTH_PASSWORD=Potatis123

    depends_on:

      - ingress

      - api

    logging:

      driver: json-file

      options:

        max-size: "100m"

        max-file: "2"



  mqtt:

    image: eclipse-mosquitto:1.6.13

    restart: always

    ports:

      - "1883:1883"

    logging:

      driver: json-file

      options:

        max-size: "100m"

        max-file: "2"



  rabbitmq:

    image: rabbitmq:3.10-management

    ports:

      - "15672:15672"

      - "5672:5672"

    restart: always

    logging:

      driver: json-file

      options:

        max-size: "100m"

        max-file: "2"



volumes:

  elasticsearch-data:

  redis-volume:



secrets:

  secret-proxy-certificate:

    file: /export/dev.localhost.crt

  secret-proxy-key:

    file: /export/dev.localhost.key

