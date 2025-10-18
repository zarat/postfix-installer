echo "[***] Setze Installer Variablen"

echo "postfix postfix/main_mailer_type string Internet Site" | sudo debconf-set-selections
echo "postfix postfix/mailname string $(hostname -f)" | sudo debconf-set-selections

echo "[***] Installiere Postfix"
sudo DEBIAN_FRONTEND=noninteractive apt install -y postfix > /dev/null 2>&1

echo "[***] Setze Postfix auf Autostart"
sudo systemctl enable postfix > /dev/null 2>&1

echo "[***] Installiere LibSASL"
sudo apt install -y libsasl2-modules sasl2-bin > /dev/null 2>&1

 echo "[***] Konfiguriere SASL um gegen PAM zu authentifizieren"
# SASL soll gegen PAM authentifizieren. (lokale User)
sudo sed -i 's/^START=.*/START=yes/' /etc/default/saslauthd
sudo sed -i 's/^MECHANISMS=.*/MECHANISMS="pam"/' /etc/default/saslauthd

echo "[***] Setze saslauthd auf Autostart"
sudo systemctl enable --now saslauthd > /dev/null 2>&1
# sudo systemctl status saslauthd

echo "[***] Fuege postfix User zu Gruppe sasl hinzu"
# Postfix user muss in die SASL Gruppe!
sudo adduser postfix sasl

echo "[***] Erstelle SASL Konfiguration fuer Postfix"
# SASL Konfiguration für Postfix erstellen
sudo mkdir -p /etc/postfix/sasl
sudo tee /etc/postfix/sasl/smtpd.conf >/dev/null <<'EOF'
pwcheck_method: saslauthd
mech_list: PLAIN LOGIN
log_level: 7
EOF

echo "[***] Aktiviere SASL serverseitig (inbound)"
# SASL serverseitig einschalten
sudo postconf -e "smtpd_sasl_auth_enable = yes"
sudo postconf -e "smtpd_sasl_type = cyrus"
sudo postconf -e "smtpd_sasl_security_options = noanonymous"
sudo postconf -e "broken_sasl_auth_clients = yes"
 
# WICHTIG: Keine TLS-Pflicht für AUTH (sonst ohne Zertifikat kein AUTH)
sudo postconf -e "smtpd_tls_auth_only = no"
sudo postconf -e "smtpd_use_tls = no"
sudo postconf -e "smtpd_tls_security_level = none"
 
# Gegen offenes Relay absichern (nur mynetworks ODER authentifiziert)
sudo postconf -e "smtpd_relay_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination"

echo "[***] Smarthost konfigurieren"
# Relay Host konfigurieren. Kein AUTH! Postfix dürfen am Exchange anonym senden. Evtl aendern. 
sudo postconf -e "relayhost = vie-srv-ex02.d2000.local"
#sudo postconf -e "fallback_relay = vie-srv-ex01.d2000.local"

echo "[***] Proxy-Protocol aktivieren"
# proxy-protocol konfigurieren
sudo postconf -e "smtpd_upstream_proxy_protocol = haproxy"
sudo postconf -e "smtpd_upstream_proxy_timeout = 5s"
sudo postconf -e "postscreen_upstream_proxy_protocol = haproxy"
sudo postconf -e "postscreen_upstream_proxy_timeout = 5s"
 
cat <<EOF
#################################
### 1. Add this to master.cf  ###
### 2. Add users              ###
### 3. Restart Postfix        ###
#################################

smtp      inet  n       -       n       -       -       smtpd
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_upstream_proxy_protocol=haproxy
127.0.0.1:2525 inet n  -  n  -  -  smtpd
  -o smtpd_upstream_proxy_protocol=
EOF
