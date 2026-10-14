# Server image notices

Burrow Brigade is distributed under the MIT license in `/app/LICENSE`.
Its source is https://github.com/AliOsm/scarpe-worms; the image's OCI revision
label identifies the release commit.

The base image is the digest-pinned official `ruby:3.4.7-slim` image, maintained at
https://github.com/docker-library/ruby. Ruby 3.4.7's copyright, license and legal
notices are in `/usr/local/share/licenses/ruby/`; source is available at
https://cache.ruby-lang.org/pub/ruby/3.4/ruby-3.4.7.tar.gz. Ruby's default gems
and the logger 1.7.0 and base64 0.3.0 gems retain their license files under
`/usr/local/lib/ruby/gems/3.4.0/gems/`.

Debian libraries retain copyright/license notices under `/usr/share/doc/`.
Corresponding Debian sources are available from https://sources.debian.org/;
`dpkg-query -W` inside the image identifies the installed package versions.
Libraries remain dynamically linked and replaceable. This headless image does
not contain Scarpe, Rust renderer crates, OpenAL, game fonts or desktop assets.
