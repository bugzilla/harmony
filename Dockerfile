FROM perl:5.32-slim AS builder

ENV DEBIAN_FRONTEND noninteractive
ENV LOG4PERL_CONFIG_FILE=log4perl-json.conf

RUN apt-get update
RUN apt-get install -y \
    apt-file \
    build-essential \
    cmake \
    curl \
    default-libmysqlclient-dev \
    git \
    libcairo-dev \
    libexpat-dev \
    libgd-dev \
    libssl-dev \
    openssl \
    zlib1g-dev

RUN cpanm --notest --quiet App::cpm Module::CPANfile Carton::Snapshot

# we run a loopback logging server on this TCP port.
ENV LOGGING_PORT=5880

WORKDIR /opt/bugzilla
COPY cpanfile cpanfile.snapshot /opt/bugzilla/
RUN cpm install


RUN apt-file update
RUN find local -name '*.so' -exec ldd {} \; \
    | egrep -v 'not.found|not.a.dynamic.executable' \
    | awk '$3 {print $3}' \
    | sort -u \
    | xargs -IFILE apt-file search -l FILE \
    | sort -u > PACKAGES

FROM perl:5.32-slim

WORKDIR /opt/bugzilla
COPY --from=builder /opt/bugzilla/PACKAGES /PACKAGES
RUN apt-get update \
    && apt-get install -y \
       curl \
       git \
       graphviz \
       libcap2-bin \
       rsync \
       $(cat /PACKAGES) \
    && rm -rf /var/cache/apt/* /var/lib/apt/lists/* /PACKAGES

COPY . /opt/bugzilla
COPY --from=builder /opt/bugzilla/local /opt/bugzilla/local
RUN dd if=/dev/urandom bs=12 count=1 | base64 > admin-password.txt && echo "Generated admin password: $(cat admin-password.txt)"
RUN { \
    printf '$answer{"urlbase"} = "http://localhost/";\n' ; \
    printf '$answer{"db_driver"} = "sqlite";\n' ; \
    printf '$answer{"ADMIN_EMAIL"} = "bugzilla-admin\\@bugzilla.local";\n' ; \
    printf '$answer{"ADMIN_PASSWORD"} = "%s";\n' "$(cat admin-password.txt)" ; \
    }  | perl checksetup.pl --default-localconfig --no-templates /dev/stdin

VOLUME ["/opt/bugzilla/data", "/opt/bugzilla/graphs"]

ENTRYPOINT ["/opt/bugzilla/bugzilla.pl"]
