# Autorun de instalação do Archlinux

### Organização do projeto
    unattend_arch/
    ├── config.json                          // configuração do archinstall
    ├── creds.json                           // template
    ├── .gitignore
    └── build/
        ├── build-iso.sh                     // script principal (roda no WSL)
        ├── docker-entrypoint.sh             // roda DENTRO do Docker
        └── overlay/
            ├── root/
            │   └── install.sh               // script de instalação no boot
            └── etc/systemd/system/
            └── archinstall-auto.service    // serviço que dispara install.sh

### Como usar
1. No WSL (Arch ou Ubuntu), tornar executável
```bash
chmod +x build/build-iso.sh
```

2. Rodar o builder
```bash
bash build/build-iso.sh
```
O script vai pedir interativamente:
- SSID e senha do WiFi
- Senha para o usuário matheus
Depois roda o Docker com archlinux:latest, constrói a ISO e salva em build/output/.

3. Flashear com dd (Linux) ou Rufus (Windows, modo DD, GPT+UEFI)
```bash
sudo dd if=build/output/archlinux-jarvis-*.iso of=/dev/sdX bs=4M status=progress
```

4. Dar boot no PC alvo pelo USB → instalação acontece sozinha

### O que acontece automaticamente no boot
1. NetworkManager conecta ao WiFi pré-configurado
2. archinstall-auto.service aguarda network-online.target
3. install.sh aguarda ping para archlinux.org (até 3 min)
4. archinstall --silent executa com config.json + creds.json gerados
5. Máquina reinicia no Arch Linux instalado com GNOME


### Segurança
- Senha de matheus é hasheada com openssl passwd -6 dentro do Docker — nunca fica em texto plano em disco
- creds.json está no .gitignore
- WiFi SSID/senha só existem na ISO gerada, não no repositório
