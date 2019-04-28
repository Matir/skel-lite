#!/usr/bin/env bash

set -o nounset
set -o errexit

case $(uname) in
  Linux)
    FINDTYPE="-xtype"
    ;;
  Darwin|*BSD)
    FINDTYPE="-type"
    ;;
  *)
    echo "Unknown OS: $(uname), guessing no GNU utils."
    FINDTYPE="-type"
    ;;
esac

is_comment() {
  if [ $(echo "${1}" | cut -c1-1) = '#' ] ; then
    true
  else
    false
  fi
}

install_dotfile_dir() {
  local SRCDIR="${1}"
  local dotfile
  find "${SRCDIR}" \( -name .git -o \
                    -path "${SRCDIR}/private_dotfiles" -o \
                    -name install.sh -o \
                    -name README.md -o \
                    -name .gitignore \) \
      -prune -o ${FINDTYPE} f -print | \
    while read dotfile ; do
      local TARGET="${HOME}/.${dotfile#${SRCDIR}/}"
      mkdir -p `dirname "${TARGET}"`
      ln -s -f "${dotfile}" "${TARGET}"
    done
}

install_basic_dir() {
  local SRCDIR="${1}"
  local DESTDIR="${2}"
  local file
  find "${SRCDIR}" ${FINDTYPE} f -print | \
    while read file ; do
    local TARGET="${2}/${file#${SRCDIR}/}"
    mkdir -p `dirname "${TARGET}"`
    ln -s -f "${file}" "${TARGET}"
  done
}

install_git() {
  # Install or update a git repository
  if ! which git > /dev/null ; then
    return 1
  fi
  local REPO="${*: -2:1}"
  local DESTDIR="${*: -1:1}"
  set -- ${@:1:$(($#-2))}
  if [ -d ${DESTDIR}/.git ] ; then
    ( cd ${DESTDIR} ; git pull -q )
  else
    if [ ${MINIMAL} -eq 1 ] ; then
      git clone --depth 1 $* ${REPO} ${DESTDIR}
    else
      git clone $* ${REPO} ${DESTDIR}
    fi
  fi
}

add_bin_symlink() {
  local LINKNAME=${HOME}/bin/${2:-`basename $1`}
  if [ -e ${LINKNAME} -a ! -h ${LINKNAME} ] ; then
    echo "Refusing to overwrite ${LINKNAME}" >&2
    return 1
  fi
  ln -sf ${1} ${LINKNAME}
}

is_deb_system() {
  test -f /usr/bin/apt-get
}

run_as_root() {
  # Attempt to run as root
  if [ ${USER} = "root" ] ; then
    "$@"
    return $?
  elif test -x $(which sudo 2>/dev/null) ; then
    verbose "Using sudo to run ${1}..."
    sudo "$@"
    return $?
  fi
  return 1
}

cleanup() {
  # Needs zsh
  if ! test -x /usr/bin/zsh ; then
    return 0
  fi
  /usr/bin/zsh >/dev/null 2>&1 <<EOF
  source ${BASEDIR}/dotfiles/zshrc.d/prune-broken-symlinks.zsh
  prune-broken-symlinks -y ${HOME}/.zshrc.d
  prune-broken-symlinks -y ${HOME}/bin
EOF
}

verbose() {
  test ${VERBOSE:-0} = 1 && echo "$@" >&2 || return 0
}

# Operations

install_dotfiles() {
  install_dotfile_dir "${BASEDIR}/dotfiles"
  test -d "${BASEDIR}/private_dotfiles" && \
    test -d "${BASEDIR}/.git/git-crypt" && \
    install_dotfile_dir "${BASEDIR}/private_dotfiles" || \
    true
  test -d "${BASEDIR}/local_dotfiles" && \
    install_dotfile_dir "${BASEDIR}/local_dotfiles" || \
    true
}

install_main() {
  install_dotfiles
  install_basic_dir "${BASEDIR}/bin" "${HOME}/bin"
  cleanup
}

# Setup variables
read_saved_prefs

# Defaults if not passed in or saved.
# TODO: use flags instead of environment variables.
BASEDIR=${BASEDIR:-$HOME/.skel}
MINIMAL=${MINIMAL:-0}
VERBOSE=${VERBOSE:-0}

# Check prerequisites
if [ ! -d $BASEDIR ] ; then
  echo "Please install to $BASEDIR!" 1>&2
  exit 1
fi

if which dpkg-query > /dev/null 2>&1 ; then
  HAVE_X=$(dpkg-query -s xserver-xorg 2>/dev/null | \
    grep -c 'Status.*installed' \
    || true)
else
  HAVE_X=0
fi

IS_KALI=$(grep -ci kali /etc/os-release 2>/dev/null || true)
ARCH=$(uname -m)

OPERATION=${1:-install}

case $OPERATION in
  install)
    install_main
    ;;
  dotfiles)
    install_dotfiles
    ;;
  test)
    # Do nothing, just sourcing
    set +o errexit
    ;;
  *)
    echo "Unknown operation $OPERATION." >/dev/stderr
    exit 1
    ;;
esac
