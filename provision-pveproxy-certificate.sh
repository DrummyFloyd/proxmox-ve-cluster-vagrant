#!/bin/bash
set -eux

ip=$1
domain=$(hostname --fqdn)
dn=$(hostname)
ca_file_name='example-ca'
ca_common_name='Example CA'

mkdir -p /vagrant/shared/$ca_file_name
pushd /vagrant/shared/$ca_file_name

# create the CA certificate.
if [ ! -f $ca_file_name-crt.pem ]; then
    openssl genrsa \
        -out $ca_file_name-key.pem \
        2048 \
        2>/dev/null
    chmod 400 $ca_file_name-key.pem
    openssl req -new \
        -sha256 \
        -subj "/CN=$ca_common_name" \
        -key $ca_file_name-key.pem \
        -out $ca_file_name-csr.pem
    openssl x509 -req -sha256 \
        -signkey $ca_file_name-key.pem \
        -extensions a \
        -extfile <(echo "[a]
            basicConstraints=critical,CA:TRUE,pathlen:0
            keyUsage=critical,digitalSignature,keyCertSign,cRLSign
            ") \
        -days 365 \
        -in  $ca_file_name-csr.pem \
        -out $ca_file_name-crt.pem
    openssl x509 \
        -in $ca_file_name-crt.pem \
        -outform der \
        -out $ca_file_name-crt.der
    # dump the certificate contents (for logging purposes).
    #openssl x509 -noout -text -in $ca_file_name-crt.pem
fi

# create the server certificate.
if [ ! -f $domain-crt.pem ]; then
    openssl genrsa \
        -out $domain-key.pem \
        2048 \
        2>/dev/null
    chmod 400 $domain-key.pem
    openssl req -new \
        -sha256 \
        -subj "/CN=$domain" \
        -key $domain-key.pem \
        -out $domain-csr.pem
    openssl x509 -req -sha256 \
        -CA $ca_file_name-crt.pem \
        -CAkey $ca_file_name-key.pem \
        -CAcreateserial \
        -extensions a \
        -extfile <(echo "[a]
            subjectAltName=DNS:$domain,IP:$ip
            extendedKeyUsage=critical,serverAuth
            ") \
        -days 365 \
        -in  $domain-csr.pem \
        -out $domain-crt.pem
    openssl pkcs12 -export \
        -keyex \
        -inkey $domain-key.pem \
        -in $domain-crt.pem \
        -certfile $domain-crt.pem \
        -passout pass: \
        -out $domain-key.p12
    # dump the certificate contents (for logging purposes).
    #openssl x509 -noout -text -in $domain-crt.pem
    #openssl pkcs12 -info -nodes -passin pass: -in $domain-key.p12
fi

# install the certificate.
# see https://pve.proxmox.com/wiki/HTTPS_Certificate_Configuration_(Version_4.x_and_newer)
cp $domain-key.pem "/etc/pve/nodes/$dn/pveproxy-ssl.key"
cp $domain-crt.pem "/etc/pve/nodes/$dn/pveproxy-ssl.pem"
systemctl restart pveproxy
# dump the TLS connection details and certificate validation result.
(printf 'GET /404 HTTP/1.0\r\n\r\n'; sleep .1) | openssl s_client -CAfile $ca_file_name-crt.pem -connect $domain:8006 -servername $domain
