{ config, lib, pkgs, ... }:

{

  systemd.services.create-immich-pod = with config.virtualisation.oci-containers; {
    serviceConfig.Type = "oneshot";
    wantedBy = [ "${backend}-immich-database.service" ];
    script = ''
      #${pkgs.podman}/bin/podman pod exists immich || \
      ${pkgs.podman}/bin/podman pod create --replace --name 'immich' --publish '2283:3001'
    '';
  };

  virtualisation.podman.defaultNetwork.settings.dns_enabled = true;
  virtualisation.podman.autoPrune.enable = true;

  virtualisation.oci-containers = {
    backend = "podman";
    containers = {

      ### Traefik ###
      traefik = {
        image = "docker.io/library/traefik:latest";
          volumes = [
        "/run/user/1000/podman/podman.sock:/var/run/docker.sock:z"
        "/storage/containers/traefik/acme.json:/acme.json:z"
        ];
        ports = [
          "80:80"
          "443:443"
          "8081:8080"
        ];
        extraOptions = [
          "--network=podman"
          "--security-opt=label=type:container_runtime_t"
        ];
        environment = {
          CLOUDFLARE_EMAIL = "";
          CLOUDFLARE_DNS_API_TOKEN = "";
        };
        cmd = [
          "--api.dashboard=true"
          "--api.insecure=true"
          "--certificatesresolvers.lets-encrypt.acme.storage=/acme.json"
          "--certificatesresolvers.lets-encrypt.acme.tlschallenge=true"
          "--certificatesresolvers.le.acme.dnschallenge.provider=cloudflare"
          "--entrypoints.http.address=:80"
          "--entrypoints.http.http.redirections.entryPoint.to=https"
          "--entrypoints.http.http.redirections.entryPoint.scheme=https"
          "--entrypoints.https.address=:443"
          "--providers.docker=true"
        ];
      };

      ### HOME ASSISTANT ###
      homeassistant = {
        volumes = [ "/storage/containers/home-assistant:/config" ];
        environment.TZ = "Pacific/Auckland";
        image = "ghcr.io/home-assistant/home-assistant:2024.4.3"; # Warning: if the tag does not change, the image will not be updated 
        extraOptions = [ "--network=host" ];
      };

      ### ESPHOME ###
      esphome = {
        volumes = [ "/storage/containers/esphome:/config" ];
        environment = {
          TZ = "Pacific/Auckland";
          ESPHOME_DASHBOARD_USE_PING = "true";
        };
        image = "ghcr.io/esphome/esphome:2024.4.0";
        # ports = [ "6052:6052" ];
        extraOptions = [ "--network=host" ];
      };

      ### VAULTWARDEN ###
      vaultwarden = {
        volumes = [ "/storage/containers/vaultwarden:/data" ];
        environment.TZ = "Pacific/Auckland";
        image = "ghcr.io/dani-garcia/vaultwarden:1.30.5"; # Warning: if the tag does not chan> 
        ports = [ "8808:80" ];
      };

      ### DECONZ ###
      deconz = {
        volumes = [ "/storage/containers/deconz/deconz-data:/opt/deCONZ" ];
        ports = [
          "8088:8088"
          "4430:4430"
          "6080:6080"
          "5999:5999"
        ];
        environment = {
          DECONZ_WEB_PORT = "8088";
          DECONZ_WS_PORT = "4430";
          DEBUG_INFO = "1";
          DEBUG_APS = "0";
          DEBUG_ZCL = "0";
          DEBUG_ZDP = "0";
          DEBUG_OTAU = "0";
          DECONZ_NOVNC_PORT = "6080";
          DECONZ_VNC_MODE = "1";
          DECONZ_VNC_PORT = "5999";
          DECONZ_VNC_PASSWORD = "deconz";
        };
        image = "ghcr.io/deconz-community/deconz-docker:2.26.3"; # Warning: if the tag does not change, the image will not be updated 
        extraOptions = [ "--device=/dev/ttyACM0" ];
      };

      ### FRIGATE ###
      frigate-nvr = {
        volumes = [
          "/storage/containers/frigate/frigate-config:/config"
          "/storage/containers/frigate/frigate-data:/media/frigate"
          "/etc/localtime:/etc/localtime:ro"
        ];
        image = "ghcr.io/blakeblackshear/frigate:stable";
        ports = [
          "5000:5000"
          "8554:8554" # RTSP feeds
          "8555:8555/tcp" # WebRTC over tcp
          "8555:8555/udp" # WebRTC over udp
        ];
        environment = {
          FRIGATE_RTSP_PASSWORD = "5gpsLvDNg2yxsn";
          PLUS_API_KEY = "efa68840-2ff0-417e-b71e-adcd07c75da9:1a5c85fd44565887fd470d16c5a409642c638949";
        };
        extraOptions = [
          "--device=/dev/bus/usb:/dev/bus/usb"
          "--mount=type=tmpfs,destination=/tmp/cache,tmpfs-size=10G"
          "--shm-size=64mb"
        ];
      };

      ### MOSQUITTO ###
      mosquitto = {
        image = "docker.io/eclipse-mosquitto";
        volumes = [ "/storage/containers/frigate/appdata/mosquitto:/mosquitto" ];
        ports = [
          "1883:1883"
          "9001:9001"
        ];
      };

      ### IMMICH ###
      immich-server = {
        volumes = [ "/storage/containers/immich/upload:/usr/src/app/upload" ];
        environmentFiles = [ "/etc/nixos/.immich-env" ];
        image = "ghcr.io/immich-app/immich-server:v1.101.0"; # Warning: if the tag does not change, the image will not be updated 
        cmd = [ "start.sh" "immich" ];
        extraOptions = [ "--pod=immich" ];
        dependsOn = [ "immich-redis" "immich-database" ];
      };
      immich-microservices = {
        volumes = [ "/storage/containers/immich/upload:/usr/src/app/upload" ];
        environmentFiles = [ "/etc/nixos/.immich-env" ];
        image = "ghcr.io/immich-app/immich-server:v1.101.0"; # Warning: if the tag does not change, the image will not be updated 
        cmd = [ "start.sh" "microservices" ];
        dependsOn = [ "immich-redis" "immich-database" ];
        extraOptions = [ "--pod=immich" ];
      };
      immich-machine-learning = {
        volumes = [ "/storage/containers/immich/model-cache:/cache" ];
        environmentFiles = [ "/etc/nixos/.immich-env" ];
        image = "ghcr.io/immich-app/immich-machine-learning:v1.101.0"; # Warning: if the tag does not change, the image will not be updated 
        dependsOn = [ "immich-redis" "immich-database" ];
        extraOptions = [ "--pod=immich" ];
      };
      immich-redis = {
        image = "registry.hub.docker.com/library/redis:6.2-alpine@sha256:51d6c56749a4243096327e3fb964a48ed92254357108449cb6e23999c37773c5";
        extraOptions = [ "--pod=immich" ];
      };
      immich-database = {
        image = "registry.hub.docker.com/tensorchord/pgvecto-rs:pg14-v0.2.0@sha256:90724186f0a3517cf6914295b5ab410db9ce23190a2d9d0b9dd6463e3fa298f0";
        #environmentFiles = [ "/etc/nixos/.immich-env" ];
        environment = {
          POSTGRES_PASSWORD = "Tuba7dXCdVnQDJ";
          POSTGRES_USER = "postgres";
          POSTGRES_DB = "immich";
        };
        volumes = [ "/storage/containers/immich/pgdata:/var/lib/postgresql/data" ];
        extraOptions = [ "--pod=immich" ];
      };

      ### UNIFI-NETWORK-APPLICATION ###
      unifi-network-application = {
        image = "ghcr.io/linuxserver/unifi-network-application:8.1.113-ls36";
        environment = {
          PUID = "1000";
          PGID = "1000";
          TZ = "Pacific/Auckland";
          MONGO_USER = "unifi";
          MONGO_PASS = "unifi";
          MONGO_HOST = "192.168.1.4";
          MONGO_PORT = "27017";
          MONGO_DBNAME = "unifi";
          #          MEM_LIMIT = "1024"; #optional
          #          MEM_STARTUP = "1024"; #optional
        };
        volumes = [ "/storage/containers/unifi-network-application/data:/config" ];
        ports = [
          "8443:8443"
          "3478:3478/udp"
          "10001:10001/udp"
          "8080:8080"
          #"1900:1900/udp" #optional
          "8843:8843" #optional
          "8880:8880" #optional
          "6789:6789" #optional
          "5514:5514/udp" #optional
        ];
      };
      unifi-db = {
        image = "docker.io/mongo:7.0.8";
        ports = [ "27017:27017" ];
        volumes = [
          "/storage/containers/unifi-network-application/database:/data/db"
          "/storage/containers/unifi-network-application/init-mongo.js:/docker-entrypoint-initdb.d/init-mongo.js:ro"
        ];
      };

      jellyfin = {
        image = "docker.io/linuxserver/jellyfin";
        environment = {
          PUID = "1000";
          PGID = "1000";
          TZ = "Pacific/Auckland";
        };
        ports = [ "8096:8096" ];
        volumes = [
          "/storage/containers/jellyfin/data/jellyfin/config:/config"
          "/storage/containers/jellyfin/media/tvseries:/data/tvshows"
          "/storage/containers/jellyfin/media/movies:/data/movies"
        ];
      };

      ### END OF CONTAINERS ###
    };
  };
}
