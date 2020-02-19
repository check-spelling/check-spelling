FROM debian:9.5-slim

RUN\
 DEBIAN_FRONTEND=noninteractive apt-get -qq update < /dev/null > /dev/null &&\
 DEBIAN_FRONTEND=noninteractive apt-get install -qq curl git jq < /dev/null > /dev/null

WORKDIR /app
COPY \
 check-pull-requests.sh \
 docker-setup.sh \
 exclude.pl \
 porcelain.pl \
 reporter.json \
 reporter.pl \
 spelling-unknown-word-splitter.pl \
 unknown-words.sh \
 ./

RUN ./docker-setup.sh &&\
 rm docker-setup.sh

LABEL "com.github.actions.name"="Spell Checker"\
 "com.github.actions.description"="Check repository for spelling errors"\
 "com.github.actions.icon"="edit-3"\
 "com.github.actions.color"="red"\
 "repository"="http://github.com/jsoref/spelling-action"\
 "homepage"="http://github.com/jsoref/spelling-action/tree/master/README.md"\
 "maintainer"="Josh Soref <jsoref@noreply.users.github.com>"

ENTRYPOINT ["/app/unknown-words.sh"]
