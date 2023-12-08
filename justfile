set positional-arguments

watch +args='test':
  cargo watch --clear --exec '{{args}}'

ci: clippy forbid
  cargo fmt -- --check
  cargo test --all
  cargo test --all -- --ignored

forbid:
  ./bin/forbid

fmt:
  cargo fmt --all

clippy:
  cargo clippy --all --all-targets -- -D warnings

lclippy:
  cargo lclippy --all --all-targets -- -D warnings

deploy branch remote chain domain:
  ssh root@{{domain}} "mkdir -p deploy \
    && apt-get update --yes \
    && apt-get upgrade --yes \
    && apt-get install --yes git rsync"
  rsync -avz deploy/checkout root@{{domain}}:deploy/checkout
  ssh root@{{domain}} 'cd deploy && ./checkout {{branch}} {{remote}} {{chain}} {{domain}}'

deploy-mainnet-balance branch="master" remote="ordinals/ord": (deploy branch remote "main" "balance.ordinals.net")

deploy-mainnet-equilibrium branch="master" remote="ordinals/ord": (deploy branch remote "main" "equilibrium.ordinals.net")

deploy-mainnet-stability branch="master" remote="ordinals/ord": (deploy branch remote "main" "stability.ordinals.net")

deploy-signet branch="master" remote="ordinals/ord": (deploy branch remote "signet" "signet.ordinals.net")

deploy-testnet branch="master" remote="ordinals/ord": (deploy branch remote "test" "testnet.ordinals.net")

save-ord-dev-state domain="ordinals-dev.com":
  $EDITOR ./deploy/save-ord-dev-state
  scp ./deploy/save-ord-dev-state root@{{domain}}:~
  ssh root@{{domain}} "./save-ord-dev-state"

log unit="ord" domain="ordinals.net":
  ssh root@{{domain}} 'journalctl -fu {{unit}}'

test-deploy:
  ssh-keygen -f ~/.ssh/known_hosts -R 192.168.56.4
  vagrant up
  ssh-keyscan 192.168.56.4 >> ~/.ssh/known_hosts
  rsync -avz \
    --delete \
    --exclude .git \
    --exclude target \
    --exclude .vagrant \
    --exclude index.redb \
    . root@192.168.56.4:ord
  ssh root@192.168.56.4 'cd ord && ./deploy/setup'

time-tests:
  cargo +nightly test -- -Z unstable-options --report-time

profile-tests:
  cargo +nightly test -- -Z unstable-options --report-time \
    | sed -n 's/^test \(.*\) ... ok <\(.*\)s>/\2 \1/p' | sort -n \
    | tee test-times.txt

fuzz:
  #!/usr/bin/env bash
  set -euxo pipefail
  cd fuzz
  while true; do
    cargo +nightly fuzz run transaction-builder -- -max_total_time=60
    cargo +nightly fuzz run runestone-decipher -- -max_total_time=60
    cargo +nightly fuzz run varint-decode -- -max_total_time=60
    cargo +nightly fuzz run varint-encode -- -max_total_time=60
  done

decode txid:
  bitcoin-cli getrawtransaction {{txid}} | xxd -r -p - | cargo run decode

open:
  open http://localhost

doc:
  cargo doc --all --open

prepare-release revision='master':
  #!/usr/bin/env bash
  set -euxo pipefail
  git checkout {{ revision }}
  git pull origin {{ revision }}
  echo >> CHANGELOG.md
  git log --pretty='format:- %s' >> CHANGELOG.md
  $EDITOR CHANGELOG.md
  $EDITOR Cargo.toml
  VERSION=`sed -En 's/version[[:space:]]*=[[:space:]]*"([^"]+)"/\1/p' Cargo.toml | head -1`
  cargo check
  git checkout -b release-$VERSION
  git add -u
  git commit -m "Release $VERSION"
  gh pr create --web

publish-release revision='master':
  #!/usr/bin/env bash
  set -euxo pipefail
  rm -rf tmp/release
  git clone https://github.com/ordinals/ord.git tmp/release
  cd tmp/release
  git checkout {{ revision }}
  cargo publish
  cd ../..
  rm -rf tmp/release

publish-tag-and-crate revision='master':
  #!/usr/bin/env bash
  set -euxo pipefail
  rm -rf tmp/release
  git clone git@github.com:ordinals/ord.git tmp/release
  cd tmp/release
  git checkout {{revision}}
  VERSION=`sed -En 's/version[[:space:]]*=[[:space:]]*"([^"]+)"/\1/p' Cargo.toml | head -1`
  git tag -a $VERSION -m "Release $VERSION"
  git push git@github.com:ordinals/ord.git $VERSION
  cargo publish
  cd ../..
  rm -rf tmp/release

list-outdated-dependencies:
  cargo outdated -R
  cd test-bitcoincore-rpc && cargo outdated -R

update-modern-normalize:
  curl \
    https://raw.githubusercontent.com/sindresorhus/modern-normalize/main/modern-normalize.css \
    > static/modern-normalize.css

download-log unit='ord' host='ordinals.net':
  ssh root@{{host}} 'mkdir -p tmp && journalctl -u {{unit}} > tmp/{{unit}}.log'
  rsync --progress --compress root@{{host}}:tmp/{{unit}}.log tmp/{{unit}}.log

download-index unit='ord' host='ordinals.net':
  rsync --progress --compress root@{{host}}:/var/lib/{{unit}}/index.redb tmp/{{unit}}.index.redb

graph log:
  ./bin/graph $1

flamegraph dir=`git branch --show-current`:
  ./bin/flamegraph $1

benchmark index height-limit:
  ./bin/benchmark $1 $2

benchmark-revision rev:
  ssh root@ordinals.net "mkdir -p benchmark \
    && apt-get update --yes \
    && apt-get upgrade --yes \
    && apt-get install --yes git rsync"
  rsync -avz benchmark/checkout root@ordinals.net:benchmark/checkout
  ssh root@ordinals.net 'cd benchmark && ./checkout {{rev}}'

benchmark-branch branch:
  #/usr/bin/env bash
  # rm -f master.redb
  rm -f {{branch}}.redb
  # git checkout master
  # cargo build --release
  # time ./target/release/ord --index master.redb index update
  # ll master.redb
  git checkout {{branch}}
  cargo build --release
  time ./target/release/ord --index {{branch}}.redb index update
  ll {{branch}}.redb

build-snapshots:
  #!/usr/bin/env bash
  set -euxo pipefail
  rm -rf tmp/snapshots
  mkdir -p tmp/snapshots
  cargo build --release
  cp ./target/release/ord tmp/snapshots
  cd tmp/snapshots
  for start in {0..750000..50000}; do
    height_limit=$((start+50000))
    if [[ -f $start.redb ]]; then
      cp -c $start.redb index.redb
    fi
    a=`date +%s`
    time ./ord --data-dir . --height-limit $height_limit index
    b=`date +%s`
    mv index.redb $height_limit.redb
    printf "$height_limit\t$((b - a))\n" >> time.txt
  done

serve-docs: build-docs
  open http://127.0.0.1:8080
  python3 -m http.server --directory docs/build/html --bind 127.0.0.1 8080

build-docs:
  #!/usr/bin/env bash
  mdbook build docs -d build
  for lang in "de" "fr" "es" "pt" "ru" "zh" "ja" "ko" "fil" "ar" "hi" "it"; do
    MDBOOK_BOOK__LANGUAGE=$lang \
      mdbook build docs -d build/$lang
    mv docs/build/$lang/html docs/build/html/$lang
  done

update-changelog:
  echo >> CHANGELOG.md
  git log --pretty='format:- %s' >> CHANGELOG.md

preview-examples:
  cargo run preview examples/*

convert-logo-to-favicon:
  convert -background none -resize 256x256 logo.svg static/favicon.png

update-mdbook-theme:
  curl https://raw.githubusercontent.com/rust-lang/mdBook/v0.4.35/src/theme/index.hbs > docs/theme/index.hbs

audit-cache:
  cargo run --package audit-cache
