TARSNAP_URL     ?= https://www.tarsnap.com/download/tarsnap-autoconf-1.0.35.tgz
TARSNAP_ARCHIVE := $(shell basename "${TARSNAP_URL}")
TARSNAP_BASE    := $(shell basename "${TARSNAP_ARCHIVE}" .tgz)
TARSNAP_STOW    := /usr/local/stow/${TARSNAP_BASE}
.DEFAULT_GOAL   := ${TARSNAP_BASE}
.PHONY          := clean prerequisites realclean stow

${TARSNAP_ARCHIVE}:
	curl --location --output "${TARSNAP_ARCHIVE}" "${TARSNAP_URL}"

${TARSNAP_BASE}: ${TARSNAP_ARCHIVE}
	make prerequisites
	tar zxvf "${TARSNAP_ARCHIVE}"
	cd "${TARSNAP_BASE}" ; ./configure --prefix="/usr/local/stow/${TARSNAP_BASE}"
	cd "${TARSNAP_BASE}" ; make

clean:
	rm -rf "${TARSNAP_BASE}"

prerequisites:
	dpkg -s build-essential >/dev/null || sudo aptitude install build-essential
	dpkg -s e2fslibs-dev    >/dev/null || sudo aptitude install e2fslibs-dev
	dpkg -s libssl-dev      >/dev/null || sudo aptitude install libssl-dev
	dpkg -s zlib1g-dev      >/dev/null || sudo aptitude install zlib1g-dev

realclean: clean
	rm -f "${TARSNAP_ARCHIVE}"

stow: ${TARSNAP_BASE}
	mkdir -p "${TARSNAP_STOW}"
	cd "${TARSNAP_BASE}" ; make install
	sudo chown -R root:staff "${TARSNAP_STOW}"
	cd "${TARSNAP_STOW}/.." ; sudo stow -v "${TARSNAP_BASE}"
