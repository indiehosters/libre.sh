#!/usr/bin/env bash
# Provision an application for a user for IndiePaaS
#
# This file:
#  - Registers the domain name to NameCheap
#  - Generates the TLS certificate associated
#  - Configures the DNS
#  - Configures the mail forwarding
#
# Version 0.0.3
#
# Authors:
#  - Pierre Ozoux (pierre-o.fr)
#
# Usage:
#  LOG_LEVEL=7 ./provision.sh -e test@test.org -a known -u example.org -g -b -c
#
# Licensed under AGPLv3


### Configuration
#####################################################################

# Environment variables and their defaults
LOG_LEVEL="${LOG_LEVEL:-6}" # 7 = debug -> 0 = emergency

# Commandline options. This defines the usage page, and is used to parse cli
# opts & defaults from. The parsing is unforgiving so be precise in your syntax
read -r -d '' usage <<-'EOF'
  -u   [arg] URL to process. Required.
  -f   [arg] Certificate file to use.
  -g         Generates the necessary certificate.
  -p         Paste certificate from previous run.
  -b         Buys the associated domain name.
  -i         Configure OpenDKIM.
  -c         Configures DNS on Namecheap.
  -d         Enables debug mode
  -h         This page
EOF

### Functions
#####################################################################

source /data/indiehosters/utils/helpers.sh
source /data/indiehosters/utils/configure_dkim_dns.sh

function scaffold () {
  info "Creating application folder"
  mkdir -p ${APP_FOLDER}

}

function buy_domain_name () {

  not_supported_extensions=( "us" "eu" "nu" "asia" "ca" "co.uk" "me.uk" "org.uk" "com.au" "net.au" "org.au" "es" "nom.es" "com.es" "org.es" "de" "fr" )
  if [ $(contains "${not_supported_extensions[@]}" "$(TLD)") == "y" ]; then
    error "Extension .$(TLD) is not yet supported.."
    exit 1
  fi 

  info "Buying Domain name."
  arguments="&Command=namecheap.domains.create\
&DomainName=${arg_u}\
&Years=1\
&AuxBillingFirstName=${FirstName}\
&AuxBillingLastName=${LastName}\
&AuxBillingAddress1=${Address}\
&AuxBillingCity=${City}\
&AuxBillingPostalCode=${PostalCode}\
&AuxBillingCountry=${Country}\
&AuxBillingPhone=${Phone}\
&AuxBillingEmailAddress=${EmailAddress}\
&AuxBillingStateProvince=${City}\
&TechFirstName=${FirstName}\
&TechLastName=${LastName}\
&TechAddress1=${Address}\
&TechCity=${City}\
&TechPostalCode=${PostalCode}\
&TechCountry=${Country}\
&TechPhone=${Phone}\
&TechEmailAddress=${EmailAddress}\
&TechStateProvince=${City}\
&AdminFirstName=${FirstName}\
&AdminLastName=${LastName}\
&AdminAddress1=${Address}\
&AdminCity=${City}\
&AdminPostalCode=${PostalCode}\
&AdminCountry=${Country}\
&AdminPhone=${Phone}\
&AdminEmailAddress=${EmailAddress}\
&AdminStateProvince=${City}\
&RegistrantFirstName=${FirstName}\
&RegistrantLastName=${LastName}\
&RegistrantAddress1=${Address}\
&RegistrantCity=${City}\
&RegistrantPostalCode=${PostalCode}\
&RegistrantCountry=${Country}\
&RegistrantPhone=${Phone}\
&RegistrantEmailAddress=${EmailAddress}\
&RegistrantStateProvince=${City}"

  call_API ${arguments}

  info "Changing email forwarding."
  arguments="&Command=namecheap.domains.dns.setEmailForwarding\
&DomainName=${arg_u}\
&mailbox1=hostmaster\
&ForwardTo1=${EmailAddress}"

  call_API ${arguments}
}

function provision_certificate () {
  scaffold
  filename=$(basename "${arg_f}")
  extension="${filename##*.}"
  if [ "${extension}" != "pem" ]; then
    error "File extension must be pem."
    exit 1
  fi

  info "Provisionning certificate."
  cp -Ra $(dirname ${arg_f}) ${TLS_FOLDER}
  cd ${TLS_FOLDER}
  mv *.pem ${arg_u}.pem
}

function generate_certificate () {
  scaffold
  info "creating TLS ans CSR folder."
  mkdir -p ${TLS_FOLDER}/CSR

  info "Generating the key."
  openssl genrsa -out ${TLS_FOLDER}/CSR/${arg_u}.key 4096

  info "Creating the request."
  openssl req -new \
    -key ${TLS_FOLDER}/CSR/${arg_u}.key \
    -out ${TLS_FOLDER}/CSR/${arg_u}.csr \
    -subj "/C=${CountryCode}/ST=${City}/L=${City}/O=${arg_u}/OU=/CN=${arg_u}/emailAddress=${EmailAddress}"

  info "Here is your CSR, paste it in your Certificate authority interface."
  echo ""
  cat ${TLS_FOLDER}/CSR/${arg_u}.csr

  echo ""
  info "You should have received a certificate."
  info "Please paste your certificate now: (finish with ctrl-d)"

  cat > ${TLS_FOLDER}/CSR/${arg_u}.crt

  info "Concat certificate, CA and key into pem file."
  cat ${TLS_FOLDER}/CSR/${arg_u}.crt /data/indiehosters/certs/sub.class2.server.sha2.ca.pem /data/indiehosters/certs/ca-sha2.pem ${TLS_FOLDER}/CSR/${arg_u}.key > ${TLS_FOLDER}/${arg_u}.pem

  /data/indiehosters/utils/append_crt_list.sh ${arg_u}
}

function paste_certificate () {
  echo ""
  info "You should have received a certificate."
  info "Please paste your certificate now: (finish with enter and ctrl-d)"
  
  cat > ${TLS_FOLDER}/CSR/${arg_u}.crt

  info "Concat certificate, CA and key into pem file."
  cat ${TLS_FOLDER}/CSR/${arg_u}.crt /data/indiehosters/certs/sub.class2.server.sha2.ca.pem /data/indiehosters/certs/ca-sha2.pem ${TLS_FOLDER}/CSR/${arg_u}.key > ${TLS_FOLDER}/${arg_u}.pem
}

### Parse commandline options
#####################################################################

# Translate usage string -> getopts arguments, and set $arg_<flag> defaults
while read line; do
  opt="$(echo "${line}" |awk '{print $1}' |sed -e 's#^-##')"
  if ! echo "${line}" |egrep '\[.*\]' >/dev/null 2>&1; then
    init="0" # it's a flag. init with 0
  else
    opt="${opt}:" # add : if opt has arg
    init=""  # it has an arg. init with ""
  fi
  opts="${opts}${opt}"

  varname="arg_${opt:0:1}"
  if ! echo "${line}" |egrep '\. Default=' >/dev/null 2>&1; then
    eval "${varname}=\"${init}\""
  else
    match="$(echo "${line}" |sed 's#^.*Default=\(\)#\1#g')"
    eval "${varname}=\"${match}\""
  fi
done <<< "${usage}"

# Reset in case getopts has been used previously in the shell.
OPTIND=1

# Overwrite $arg_<flag> defaults with the actual CLI options
while getopts "${opts}" opt; do
  line="$(echo "${usage}" |grep "\-${opt}")"


  [ "${opt}" = "?" ] && help "Invalid use of script: ${@} "
  varname="arg_${opt:0:1}"
  default="${!varname}"

  value="${OPTARG}"
  if [ -z "${OPTARG}" ] && [ "${default}" = "0" ]; then
    value="1"
  fi

  eval "${varname}=\"${value}\""
  debug "cli arg ${varname} = ($default) -> ${!varname}"
done

shift $((OPTIND-1))

[ "$1" = "--" ] && shift


### Switches (like -d for debugmdoe, -h for showing helppage)
#####################################################################

# debug mode
if [ "${arg_d}" = "1" ]; then
  set -o xtrace
  LOG_LEVEL="7"
fi

# help mode
if [ "${arg_h}" = "1" ]; then
  # Help exists with code 1
  help "Help using ${0}"
fi


### Validation (decide what's required for running your script and error out)
#####################################################################

[ -z "${arg_u}" ]     && help      "URL is required."
[ -z "${LOG_LEVEL}" ] && emergency "Cannot continue without LOG_LEVEL."


### Runtime
#####################################################################

# Exit on error. Append ||true if you expect an error.
# set -e is safer than #!/bin/bash -e because that is neutralised if
# someone runs your script like `bash yourscript.sh`
set -o errexit
set -o nounset

# Bash will remember & return the highest exitcode in a chain of pipes.
# This way you can catch the error in case mysqldump fails in `mysqldump |gzip`
set -o pipefail

FOLDER=/data/domains/${arg_u}
TLS_FOLDER=${FOLDER}/TLS

[ ${arg_b} -eq 1 ] && buy_domain_name
[ ${arg_g} -eq 1 ] && generate_certificate
[ ${arg_p} -eq 1 ] && paste_certificate
[ ! -z "${arg_f}" ] && provision_certificate
[ ${arg_i} -eq 1 ] && provision_dkim
[ ${arg_c} -eq 1 ] && configure_dns

exit 0
