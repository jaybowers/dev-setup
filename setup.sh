#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

usage() {
    echo "Usage: ${0} other [type]"
}

while getopts ":d" option; do
    case "${option}" in
        d)
            set -o xtrace
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

file_host=${1}
desktop_type=${2:-client}

declare -A mint_to_ubuntu_releases
mint_to_ubuntu_releases[serena]=xenial

_release=$(lsb_release -c -s)
if [ ! -z ${mint_to_ubuntu_releases[${_release}]} ]; then
    _release=${mint_to_ubuntu_releases[${_release}]}
fi

_warnings=()
_tmp=/tmp/setup
mkdir -p ${_tmp}

# some random set up :-/
mkdir -p $HOME/.bashrc.d
mkdir -p $HOME/.zshrc.d

inform() {
    printf "$@"
}

checking() {
    printf "Checking %-30s..." "$*"
}
checked_ok() {
    printf "ok\n"
}
installing() {
    printf "Installing %-30s...\n" "$@"
}
installed_ok() {
    printf "Installed %-30s\n" "$@"
}

add_warnings() {
    _warnings+=("${1}")
}

show_warnings() {
    if [ ${#_warnings[*]} -gt 0 ]; then
        echo
        echo " === WARNINGS ==="
        echo
        for w in "${_warnings[*]}"
        do
            echo "${w}"
        done
    fi
}

command_exists() {
    command -v ${1} >/dev/null 2>&1
}

do_update=true
apt_update() {
    if [ ${do_update} = true ]; then
        sudo apt-get update
    fi
    do_update=false
}

apt_package_installed() {
    dpkg -s ${1} > /dev/null 2>&1
}

apt_install() {
    not_installed=()
    checking "${@}"
    for package in $@
    do
        if ! apt_package_installed ${package};  then
            not_installed+=(${package})
        fi
    done
    if [[ ${#not_installed[*]} -gt 0 ]]; then
        echo "Installing ${not_installed[@]}..."
        apt_update
        sudo apt-get install -y ${not_installed[@]}
    else
        checked_ok
    fi
}

create_ssh_key() {
    checking "ssh key"
    if [ ! -e ~/.ssh/id_rsa.pub ]; then
        installing "ssh key"
        ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa

        echo "Public key created, now copy they key into git server:"
        cat ~/.ssh/id_rsa.pub
        read -p "Press any key to continue "
        installed_ok "ssh key"
    else
        checked_ok
    fi
}

copy_ssh_key_to_file_host() {
    checking "ssh to other desktop"
    if ! ssh -o'PreferredAuthentications publickey' ${file_host} 'echo ok' > /dev/null 2>&1; then
        echo "Copying id to '${file_host}'..."
        ssh-copy-id ${file_host}
    else
        checked_ok
    fi
}

install_vim_pathogen() {
    checking "vim pathogen"
    # Look at using https://github.com/junegunn/vim-plug
    if [ ! -e  ~/.vim/autoload/pathogen.vim ]; then
        installing "vim pathogen"
        mkdir -p ~/.vim/autoload ~/.vim/bundle && \
            curl -LSso ~/.vim/autoload/pathogen.vim https://tpo.pe/pathogen.vim
        installed_ok "vim pathogen"
    else
        checked_ok
    fi
}
install_vim_plugin_onedark() {
    checking "vim color scheme onedark"
    if [ ! -e ~/.vim/bundle/onedark.vim ]; then
        installing "vim colour scheme onedark"
        git clone https://github.com/joshdick/onedark.vim.git ~/.vim/bundle/onedark.vim
        installed_ok "vim colour scheme onedark"
    else
        checked_ok
    fi
}
install_vim_templates() {
    do_vim_templates() {
        mkdir -p ~/.vim
        ln -s ${PWD}/resources/HOME/.vim/templates ~/.vim
    }

    install_file_check ~/.vim/templates do_vim_templates
}

install_rc() {
    local name=${1}
    local conf=${2:-${1}}

    local link_src=${PWD}/${name}/${conf}
    local link_dest=~/.${conf}

    clean_old_rc_link ${link_src} ${link_dest}

    checking "rc ${name}:${conf}"
    if [ ! -e ${link_dest} ]; then
        installing "${name}:${conf}"

        echo "Linking ${link_src} to ${link_dest}..."
        ln -s ${link_src} ${link_dest}
        installed_ok "${name}:${conf}"
    else
        checked_ok
    fi
}

clean_old_rc_link() {
    local link_src=$1
    local link_dest=$2
    local link_current=$(readlink ${link_dest})

    if [[ -L ${link_dest} ]] && [[ ${link_current} != ${link_src} ]]; then
        inform "Cleaning up old rc link from ${link_current} to ${link_dest}\n"
        rm ${link_dest}
    fi
}


install_tmux_tmux_plugin_manager() {
    checking "tmux pluging manager"
    if [ ! -e ~/.tmux/plugins/tpm ]; then
        installing "tmux plugin manager"
        git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
        add_warnings "TMUX: Run tmux and press 'prefix I' to load plugins"
        installed_ok "tmux plugin manager"
    else
        checked_ok
    fi
}

install_powerline_fonts() {
    checking "powerline fonts"
    if [ ! -e ~/.local/share/fonts ]; then
        installing "powerline fonts"

        git clone https://github.com/powerline/fonts.git ${_tmp}/fonts
        (
            cd ${_tmp}/fonts
            ./install.sh
        )

        # replace with 'gsettings list-recursively | grep -i org.gnome.Terminal'
        add_warnings "Powerline Fonts: Make sure that the font 'Ubuntu Mono derivative Powerline' is chosen in the terminal profile"
        installed_ok "powerline fonts"
    else
        checked_ok
    fi
}

install_oh_my_zsh() {
    checking "oh my zsh"
    if [ ! -e ~/.oh-my-zsh ]; then
        installing "oh my zsh"
        sh -c "$(wget https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh -O -)"

        sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="agnoster"/' ~/.zshrc

        installed_ok "oh my zsh"
    else
        checked_ok
    fi
}

compile_and_install_synergy() {
    checking "synergy"
    if ! command_exists synergy; then
        installing "synergy"
        local work=${_tmp}/synergy

        if ! ls ${work}/bin/synergy-master-stable-*-Linux-x86_64.deb > /dev/null 2>&1; then
            apt_install cmake make g++ xorg-dev libqt4-dev libcurl4-openssl-dev libavahi-compat-libdnssd-dev libssl-dev libx11-dev

            echo " Checkout synergy..."
            checkout_synergy ${work}

            echo " Compile synergy..."
            compile_synergy ${work}
        fi

        install_synergy $(ls ${work}/bin/synergy-master-stable-*-Linux-x86_64.deb)
        installed_ok "synergy"
    else
        checked_ok
    fi

    
    checking "synergy autostart"
    if [ ! -e ${HOME}/.config/autostart/synergy.desktop ]; then
        installing "synergy autostart"
        mkdir -p ${HOME}/.config/autostart/
        ln -s /usr/share/applications/synergy.desktop ${HOME}/.config/autostart/synergy.desktop
        installed_ok "synergy autostart"
    else
        checked_ok
    fi
}

checkout_synergy() {
    local work=${1}

    if [ ! -e ${work} ]; then
        git clone https://github.com/symless/synergy ${work}
    fi

    (
        cd ${work}
        git pull
    )

}
compile_synergy() {
    local work=${1}
    
    (
        cd ${work}
        # optionally add '-d' to build a debug version.
        QT_SELECT=4 ./hm.sh conf -g1
        ./hm.sh build [-d]
        # optionally build a package if you wish to install it system-wide with a package manager instead of running from the cli
        ./hm.sh package deb
    )
}

install_synergy() {
    local synergy_deb=${1}
    echo "Installing synergy..."
    
    echo " Installing runtime dependancies..."
    apt_update
    sudo apt-get install libavahi-compat-libdnssd1 libcurl3
    
    echo " Installing deb..."
    sudo dpkg --install ${synergy_deb}
    
    if [ "${desktop_type}" == "server" ]; then
        echo " Configuring as a synergy server..."
        echo <<EO_SYNERGY_CONFIG > ~/.synergy.conf
section: screens
    divergence:
        halfDuplexCapsLock = false
        halfDuplexNumLock = false
        halfDuplexScrollLock = false
        xtestIsXineramaUnaware = false
        switchCorners = none 
        switchCornerSize = 0
    minerva:
        halfDuplexCapsLock = false
        halfDuplexNumLock = false
        halfDuplexScrollLock = false
        xtestIsXineramaUnaware = false
        switchCorners = none 
        switchCornerSize = 0
end

section: aliases
end

section: links
    divergence:
        right = minerva
    minerva:
        left = divergence
end

section: options
    relativeMouseMoves = false
    screenSaverSync = true
    win32KeepForeground = false
    clipboardSharing = true
    switchCorners = none 
    switchCornerSize = 0
    keystroke(Control+F11) = switchToScreen(divergence)
    keystroke(Control+F12) = switchToScreen(minerva)
end
EO_SYNERGY_CONFIG
    else 
        echo " Configuring as client..."
    fi
}

install_chrome() {
    checking "chrome"
    if ! command_exists google-chrome; then
        installing "chrome"
        wget -q -O- https://dl-ssl.google.com/linux/linux_signing_key.pub | sudo apt-key add - 
        if [ ! -e /etc/apt/sources.list.d/google-chrome.list ]; then
            sudo sh -c 'echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google-chrome.list'
        fi
        sudo apt-get update
        sudo apt-get install google-chrome-stable
        installed_ok "chrome"
    else
        checked_ok
    fi
}

install_java() {
    checking "java 8"
    if ( ! command_exists java ) || ( ! java -version 2>&1 | grep "Java HotSpot" > /dev/null ); then
        installing "java 8"
        sudo apt-get install python-software-properties
        sudo add-apt-repository ppa:webupd8team/java
        sudo apt-get update

        echo "oracle-java8-installer shared/accepted-oracle-license-v1-1 select true" | sudo debconf-set-selections
        sudo apt-get install oracle-java8-installer
        sudo apt install oracle-java8-set-default

        cat > ~/.bashrc.d/java.sh <<'EO_BASH_RC'
JAVA_HOME=$(dirname $(dirname $(update-alternatives --get-selections | grep ^javac | awk '{print ${3}}' )))
EO_BASH_RC
        installed_ok "java 8"
    else
        checked_ok
    fi
}

install_maven() {
    checking "maven"
    local to="/usr/share/maven"
    local from="http://apache.mirror.triple-it.nl/maven/maven-3/3.5.0/binaries/apache-maven-3.5.0-bin.tar.gz"
    
    if ! command_exists mvn ; then
        installing "maven"
        sudo mkdir -p ${to}
        
        # Curl location of tar.gz archive & extract without first directory
        wget -q -O- ${from} | sudo tar -xzf - -C ${to} --strip 1
        
        # Creating a symbolic/soft link to Maven in the primary directory of executable commands on the system
        sudo ln -s ${to}/bin/mvn /usr/bin/mvn
        
        echo "export PATH=${to}/bin:${PATH}" > ~/.bashrc.d/maven.sh
        installed_ok "maven"
    else
        checked_ok
    fi
}

install_maven_settings() {
    checking "maven settings"
    
    to=~/.m2
    if [[ ! -e ${to}/settings.xml ]]; then
        installing "maven settings"
        mkdir -p ${to}
        
        cp resources/HOME/.m2/settings.xml ${to}
        installed_ok "maven settings"
    else
        checked_ok
    fi
}


install_eclipse() {
    checking "eclipse"
    if ! command_exists eclipse; then
        installing "eclipse"
        echo "Installing eclipse..."
        if [ ! -e ${_tmp}/eclipse.tar.gz ]; then
            echo " Downloading archive..."
            wget -q -O ${_tmp}/eclipse.tar.gz \
                http://www.mirrorservice.org/sites/download.eclipse.org/eclipseMirror/technology/epp/downloads/release/neon/3/eclipse-jee-neon-3-linux-gtk-x86_64.tar.gz
        fi
        echo " Extracting archive..."
        sudo mkdir -p /opt/eclipse/
        (
            cd /opt/eclipse
            sudo tar --extract --gzip --file ${_tmp}/eclipse*.tar.gz 
        )
        if [ ! -e /usr/local/bin/eclipse ]; then
            echo " Linking binary.."
            sudo ln -s /opt/eclipse/eclipse/eclipse /usr/local/bin/
        fi
        installed_ok "eclipse"
    else
        checked_ok
    fi

    desktop=/usr/share/applications/eclipse.desktop 
    if [[ ! -e ${desktop} ]]; then
        echo "Installing eclipse menu shortcut..."
        cat <<EO_DESKTOP | sudo tee ${desktop}
[Desktop Entry]
Type=Application
Encoding=UTF-8
Name=Eclipse
Comment=Eclipse IDE
Exec=/opt/eclipse/eclipse/eclipse
Icon=/opt/eclipse/eclipse/icon.xpm
Terminal=false
Type=Application
Categories=GNOME;Application;Development;
StartupNotify=true
EO_DESKTOP
    fi
}

install_slack() {
    checking "slack"
    local url='https://downloads.slack-edge.com/linux_releases/slack-desktop-2.6.3-amd64.deb'
    local tmp=${_tmp}/${url/*\//}
    if ! command_exists slack; then
        installing "slack"

        if [ ! -e ${tmp} ]; then
            echo " Fetching from ${url}..."
            wget -q -O ${tmp} ${url}
        fi
        echo " Installing from ${tmp}..."
        sudo dpkg --install ${tmp}
        installed_ok "slack"
    else
        checked_ok
    fi
}

install_liquidprompt() {
    checking "liquidprompt"
    if [ ! -e ~/tools/liquidprompt ]; then
        installing "liquidprompt"
        mkdir -p ~/tools/liquidprompt
        git clone https://github.com/nojhan/liquidprompt.git ~/tools/liquidprompt
        
        cat > ~/.bashrc.d/liquidprompt.sh <<'EO_BASH_RC'
# Only load Liquid Prompt in interactive shells, not from a script or from scp
[[ $- = *i* ]] && source ~/tools/liquidprompt/liquidprompt
EO_BASH_RC
        installed_ok "liquidprompt"
    else
        checked_ok
    fi
}

install_docker() {
    checking "docker"

    if ! command_exists docker; then
        installing "docker"
        sudo apt-get -y install \
          apt-transport-https \
          ca-certificates \
          curl
        
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
        
        sudo add-apt-repository \
              "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
               ${_release} \
               stable"
       
        sudo apt-get update

        sudo apt-get -y install docker-ce

        echo " Docker postinstall... "
        echo "  Docker setting up user... "
        sudo groupadd docker
        sudo usermod -aG docker ${USER}

        echo "  Docker setting up autostart... "
        sudo systemctl enable docker
        add_warnings "DOCKER: to finish the docker set up login and logout"
        installed_ok "docker"
    else
        checked_ok
    fi
}

install_gcloud_sdk() {
    checking "google cloud sdk"
    if ! command_exists gcloud ]; then
        installing "google cloud sdk"

        if [[ ! -e /etc/apt/sources.list.d/google-cloud-sdk.list ]]; then
            export CLOUD_SDK_REPO="cloud-sdk-${_release}"
            echo "deb http://packages.cloud.google.com/apt ${CLOUD_SDK_REPO} main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
            
            curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
        fi
        sudo apt-get update && sudo apt-get install google-cloud-sdk
        installed_ok "google cloud sdk"
    else
        checked_ok
    fi
    apt_install google-cloud-sdk-app-engine-java \
        google-cloud-sdk-app-engine-python \
        google-cloud-sdk-pubsub-emulator \
        google-cloud-sdk-bigtable-emulator \
        google-cloud-sdk-datastore-emulator \
        kubectl

}

install_puppet() {
    checking "puppet apt sources"
    if ! apt_package_installed puppetlabs-release-pc1;  then
        installing "puppet apt sources"

        deb_file=puppetlabs-release-pc1-${_release}.deb

        wget -q -O ${_tmp}/${deb_file} https://apt.puppetlabs.com/${deb_file}
        sudo dpkg -i ${_tmp}/${deb_file} 
        sudo apt update
        installed_ok "puppet apt sources"
    else
        checked_ok
    fi
    checking "puppetserver"
    if ! apt_package_installed puppetserver; then
        installing "Installing puppet server..."
        apt_install puppetserver

        # DONT start puppet for now
        # sudo systemctl start puppetserver
        installed_ok "Installing puppet server..."
    else
        checked_ok
    fi
}

install_fpm() {
    checking "fpm"
    if ! command_exists fpm ]; then
        installing "fpm"
        apt_install ruby ruby-dev rubygems build-essential
        sudo gem install --no-ri --no-rdoc fpm
        installed_ok "fpm"
    else
        checked_ok
    fi
}

install_command_check() {
    local command=$1
    local function=$2
    checking "$command"
    if ! command_exists "$command" ]; then
        installing "$command"
        
        $function

        installed_ok "$command"
    else
        checked_ok
    fi
}

install_file_check() {
    local file_path=$1
    local function=$2
    checking "$file_path"
    if [ ! -e "$file_path" ]; then
        installing "$file_path"
        
        $function

        installed_ok "$file_path"
    else
        checked_ok
    fi
}

install_minikube() {
    do_minikube_install() {
        curl -Lo minikube https://storage.googleapis.com/minikube/releases/v0.20.0/minikube-linux-amd64 && chmod +x minikube && sudo mv minikube /usr/local/bin/
        sudo chown root:root /usr/local/bin/minikube

        # install kvm
        sudo apt install libvirt-bin qemu-kvm
        sudo usermod -a -G libvirtd $(whoami)

        curl -L https://github.com/docker/machine/releases/download/v0.12.0-rc2/docker-machine-`uname -s`-`uname -m` >/tmp/docker-machine
        chmod +x /tmp/docker-machine &&
        sudo cp /tmp/docker-machine /usr/local/bin/docker-machine

        curl -L https://github.com/dhiltgen/docker-machine-kvm/releases/download/v0.10.0/docker-machine-driver-kvm-ubuntu16.04 > /tmp/docker-machine-driver-kvm
        sudo mv /tmp/docker-machine-driver-kvm /usr/local/bin/docker-machine-driver-kvm
        chmod +x /usr/local/bin/docker-machine-driver-kvm
        sudo chown root:root /usr/local/bin/docker-machine-driver-kvm

    }
    install_command_check minikube do_minikube_install
}

install_vagrant() {
    checking "vagrant"
    if ! command_exists vagrant; then
        installing "vagrant"
        sudo dpkg --install resources/vagrant_1.9.5_x86_64.deb
        installed_ok "vagrant"
    else
        checked_ok
    fi
}

install_dbeaver() {
    checking "dbeaver"
    if ! command_exists dbeaver; then
        installing "dbeaver"
        sudo dpkg -i resources/dbeaver-ce_4.0.8_amd64.deb
        installed_ok "dbeaver"
    else
        checked_ok
    fi
}

install_mc_tools() {
    checking "mc-config-manager"
    if ! command_exists mc-config-manager; then
        installing "mc-config-manager"
        mkdir -p ~/bin
        ln -s $PWD/resources/HOME/bin/mc-config-manager ~/bin/

        mkdir -p ~/.local/share/applications/
        cp resources/HOME/.local/share/applications/config-manager.desktop ~/.local/share/applications/

        mkdir -p ~/.configmanager
        cp resources/HOME/.configmanager/configmanager.properties.example ~/.configmanager
        add_warnings "Set up config manager properties at ~/.configmanager/configmanager.properties.example"
        
        installed_ok "mc-config-manager"
    else
        checked_ok
    fi
}

install_git_run() {
    checking "git run"
    if [ ! -e /usr/local/bin/gr ]; then
        installing "git run"

        sudo npm install -g git-run
        echo "alias gitr='/usr/local/bin/gr'" > ~/.zshrc.d/git-run.zsh

        installed_ok "git run"
    else
        checked_ok
    fi
}

install_instantclient() {
    apt_install python-dev build-essential libaio1 libaio1-dev

    if [[ ! -e /opt/ora/instantclient ]]; then
        sudo mkdir -p /opt/ora/
        local _resources=$PWD/resources
        sudo unzip -d /opt/ora/ ${_resources}/instantclient-basic-linux.x64-11.2.0.4.0.zip
        sudo unzip -d /opt/ora/ ${_resources}/instantclient-sdk-linux.x64-11.2.0.4.0.zip
        sudo unzip -d /opt/ora/ ${_resources}/instantclient-sqlplus-linux.x64-11.2.0.4.0.zip

        (
            cd /opt/ora
            sudo ln -s instantclient_11_2 instantclient
        )
        (
            cd /opt/ora/instantclient 
            sudo ln -s libclntsh.so.11.1 libclntsh.so 
        )
    fi

    sudo rm -f /etc/profile.d/oracle.sh
    cat <<'EO_ORACLE_SH' | sudo tee -a /etc/profile.d/oracle.sh
export ORACLE_HOME=/opt/ora/instantclient/
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH${LD_LIBRARY_PATH:+:}$ORACLE_HOME
export TNS_ADMIN=$ORACLE_HOME
EO_ORACLE_SH

    for f in ~/.bashrc.d/instantclient.sh ~/.zshrc.d/instantclient.zsh
    do
        rm -f $f
        echo 'source /etc/profile.d/oracle.sh' | tee -a $f
    done

    sudo cp ~/tools/fab-client-v2/extras/tnsnames.ora /opt/ora/instantclient/
}

install_fab_client_v2() {
    do_fab_client_v2() {

        apt_install python-pip python-setuptools
        sudo pip install pyxb requests tinydb tinydb_serialization wheel argcomplete

        if [ ! -e ~/tools/fab-client-v2 ]; then
            git clone git@git.office.mcom:jayb/fab-client-v2.git ~/tools/fab-client-v2
        fi

        if [ ! -e /opt/ora/instantclient ]; then
            install_instantclient
            add_warnings "FAB: Please LOG OUT Log back in and re-run this script"
        else
            sudo -s -- <<EOF
                source /etc/profile.d/oracle.sh
                pip install cx_Oracle
EOF

            for f in ~/.bashrc.d/fab.sh ~/.zshrc.d/fab.zsh
            do
                rm -f $f
                echo <<'EO_FAB_CLIENT_V2' > $f
export PYTHONPATH=${PYTHONPATH}${PYTHONPATH:+:}$HOME/tools/fab-client-v2/src/main/python

# slight hack:
autoload bashcompinit
bashcompinit

eval "$(register-python-argcomplete fab)"
EO_FAB_CLIENT_V2
            done

            sudo activate-global-python-argcomplete

            ln -s ~/tools/fab-client-v2/src/main/scripts/fab ~/bin/
            ln -s ~/tools/fab-client-v2/src/main/scripts/fab-audit ~/bin/
        fi
    }
    install_command_check fab do_fab_client_v2

    do_xmlless() {
        ln -s ~/tools/fab-client-v2/extras/xmlless ~/bin/
    }
    install_command_check xmlless do_xmlless
}

install_soapui() {
    do_soapui() {
        sudo mkdir -p /opt/soapui
        sudo tar --directory /opt/soapui -x -f resources/SoapUI-5.3.0-linux-bin.tar.gz

        desktop=/usr/share/applications/soapui.desktop 
        inform "Installing soapui menu shortcut..."
        cat <<EO_DESKTOP | sudo tee ${desktop}
[Desktop Entry]
Type=Application
Encoding=UTF-8
Name=SoapUI 5.3.0
Comment=Soap UI 
Exec=/opt/soapui/SoapUI-5.3.0/soapui.sh
Icon=/opt/soapui/SoapUI-5.3.0/bin/SoapUI-Spashscreen.png
Terminal=false
Type=Application
Categories=GNOME;Application;Development;
StartupNotify=true
EO_DESKTOP

        ln -s /opt/soapui/SoapUI-5.3.0/bin/soapui.sh ~/bin/soapui
    }
    install_command_check soapui do_soapui
}

install_jmeter() {
    do_jmeter() {
        local to="/opt/jmeter"
        local from="http://apache.proserve.nl/jmeter/binaries/apache-jmeter-3.2.tgz"

        sudo mkdir -p ${to}
        
        # Curl location of tar.gz archive & extract without first directory
        wget -q -O- ${from} | sudo tar -xzf - -C ${to} --strip 1
        
        sudo ln -s ${to}/bin/jmeter /usr/bin/jmeter
        
        echo "export PATH=${to}/bin:${PATH}" > ~/.bashrc.d/maven.sh
        echo "export PATH=${to}/bin:${PATH}" > ~/.zshrc.d/maven.sh
    }

    install_command_check jmeter do_jmeter
}

install_reviewboard_tools() {
    do_reviewboard_tools() {
        sudo pip install -U RBTools
     
        echo "DISABLE_SSL_VERIFICATION = True" > ~/.reviewboardrc
        echo "DISABLE_SSL_VERIFICATION = True" > ~/.reviewboardrc
    }

    install_command_check rbt do_reviewboard_tools
}

warn_about_vpn() {
    for vpn in client prod
    do
        if !  nmcli -color no -terse -fields NAME,TYPE connection | grep ${vpn}':vpn' > /dev/null 2>&1; then
            add_warnings "VPN: Make sure to use NetworkManager to set up the '${vpn}' VPN."
        fi
    done
}

create_ssh_key
copy_ssh_key_to_file_host

apt_install openssh-server
apt_install screen
apt_install libxml2-utils
apt_install subversion
apt_install htop
apt_install xsltproc
apt_install jq
apt_install httpie

apt_install git
install_rc gitrc gitconfig
install_rc gitrc gitignore_global
apt_install gitk

install_reviewboard_tools

apt_install vim-gtk
install_rc vimrc
install_vim_pathogen
install_vim_plugin_onedark
install_vim_templates

compile_and_install_synergy

install_chrome
install_java
install_maven
install_maven_settings
install_eclipse
install_slack

apt_install tmux
install_rc tmuxrc tmux.conf
install_tmux_tmux_plugin_manager
apt_install xsel
install_powerline_fonts

apt_install zsh
install_oh_my_zsh

install_liquidprompt

install_docker
install_gcloud_sdk
install_vagrant
install_fpm
install_minikube

install_puppet

install_dbeaver
install_mc_tools

apt_install apt-file
apt_install libsecret-tools

apt_install wireshark
apt_install meld

apt_install nodejs npm
install_git_run

apt_install source-highlight
install_fab_client_v2
install_soapui
install_jmeter

apt_install byobu
apt_install virtualbox
apt_install ansible

show_warnings
warn_about_vpn

