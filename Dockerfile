FROM ubuntu:latest

LABEL org.opencontainers.image.authors="jsnyder0"

RUN apt-get update

RUN apt-get install ipmitool -y

ADD functions.sh /app/functions.sh
ADD constants.sh /app/constants.sh
ADD healthcheck.sh /app/healthcheck.sh
ADD Dell_iDRAC_fan_controller.sh /app/Dell_iDRAC_fan_controller.sh

RUN chmod 0777 /app/functions.sh /app/healthcheck.sh /app/Dell_iDRAC_fan_controller.sh

WORKDIR /app

HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 CMD [ "/app/healthcheck.sh" ]

# you should override these default values when running. See README.md
# ENV IDRAC_HOST=192.168.1.100
ENV IDRAC_HOST=local
# ENV IDRAC_USERNAME=root
# ENV IDRAC_PASSWORD=calvin
ENV FAN_SPEED_MIN=5
ENV FAN_SPEED_MAX=50
ENV CPU_TEMPERATURE_LOWER_THRESHOLD=45
ENV CPU_TEMPERATURE_UPPER_THRESHOLD=75
ENV CHECK_INTERVAL=60
ENV ENABLE_DELL_CONTROL_ON_STARTUP=false
ENV DISABLE_THIRD_PARTY_PCIE_CARD_DELL_DEFAULT_COOLING_RESPONSE=false
ENV KEEP_THIRD_PARTY_PCIE_CARD_COOLING_RESPONSE_STATE_ON_EXIT=false

ENTRYPOINT ["./Dell_iDRAC_fan_controller.sh"]
