#!/system/bin/sh

scripts=`realpath $0`
scripts_dir=`dirname ${scripts}`
. /data/clash/clash.config

monitor_local_ipv4() {
    local_ipv4=$(ip a | awk '$1~/inet$/{print $2}')
    local_ipv4_number=$(ip a | awk '$1~/inet$/{print $2}' | wc -l)
    rules_ipv4=$(${iptables_wait} -t mangle -nvL OUTPUT | grep "RETURN" | awk '{print $9}')
    rules_number=$(${iptables_wait} -t mangle -L OUTPUT | grep "RETURN" | wc -l)

    until [ -f ${Clash_pid_file} ] ; do
        sleep 1
        for subnet in ${local_ipv4[*]} ; do
            sleep 0.5
            if (${iptables_wait} -t mangle -C OUTPUT -d ${subnet} -j RETURN > /dev/null 2>&1) ; then
                ${iptables_wait} -t mangle -D OUTPUT -d ${subnet} -j RETURN
                ${iptables_wait} -t mangle -D PREROUTING -d ${subnet} -j RETURN
                wait
            fi
        done
    done

    if [ ${local_ipv4_number} -ne ${rules_number} ] ; then
        for rules_subnet in ${rules_ipv4[*]} ; do
            wait_count=0
            a_subnet=$(ipcalc -n ${rules_subnet} | awk -F '=' '{print $2}')
            sleep 0.5
            for local_subnet in ${local_ipv4[*]} ; do
                sleep 0.5
                b_subnet=$(ipcalc -n ${local_subnet} | awk -F '=' '{print $2}')

                if [ "${a_subnet}" != "${b_subnet}" ] ; then
                    wait_count=$((${wait_count} + 1))
                    
                    if [ ${wait_count} -ge ${local_ipv4_number} ] ; then
                        ${iptables_wait} -t mangle -D OUTPUT -d ${rules_subnet} -j RETURN
                        ${iptables_wait} -t mangle -D PREROUTING -d ${rules_subnet} -j RETURN
                        wait
                    fi
                fi
            done
        done

        for subnet in ${local_ipv4[*]} ; do
            sleep 0.5
            if ! (${iptables_wait} -t mangle -C OUTPUT -d ${subnet} -j RETURN > /dev/null 2>&1) ; then
                ${iptables_wait} -t mangle -I OUTPUT -d ${subnet} -j RETURN
                ${iptables_wait} -t mangle -I PREROUTING -d ${subnet} -j RETURN
                wait
            fi
        done

        unset a_subnet
        unset b_subnet
    else
        sleep 1
    fi

    wait

    unset local_ipv4
    unset local_ipv4_number
    unset rules_ipv4
    unset rules_number
    unset wait_count
}

keep_dns() {
    local_dns=`getprop net.dns1`

    if [ "${local_dns}" != "${static_dns}" ] ; then
        setprop net.dns1 ${static_dns}
    fi

    unset local_dns
}

subscription() {
    if [ "${auto_subscription}" = "true" ] ; then
        mv -f ${Clash_config_file} ${Clash_data_dir}/config.yaml.backup
        curl -L -A 'clash' ${subscription_url} -o ${Clash_config_file} >> /dev/null 2>&1

        sleep 20

        if [ -f "${Clash_config_file}" ]; then
            rm -rf ${Clash_data_dir}/config.yaml.backup
        else
            mv ${Clash_data_dir}/config.yaml.backup ${Clash_config_file}
        fi
    fi
}

find_packages_uid() {
    if [ "${mode}" = "blacklist" ] ; then
        echo "1000 1001 1010 1014 1016" > ${appuid_file}
    elif [ "${mode}" = "whitelist" ] ; then
        echo "" > ${appuid_file}
    fi
    for package in `cat ${filter_packages_file} | sort -u` ; do
        awk '$1~/'^"${package}"$'/{print $2}' ${system_packages_file} >> ${appuid_file}
    done
}

port_detection() {
    clash_pid=`cat ${Clash_pid_file}`
    clash_port=$(ss -antup | grep "clash" | awk '$7~/'pid="${clash_pid}"*'/{print $5}' | awk -F ':' '{print $2}' | sort -u)
    match_count=0
    for sub_port in ${clash_port[*]} ; do
        sleep 0.5
        if [ "${sub_port}" = ${Clash_tproxy_port} ] || [ "${sub_port}" = ${Clash_dns_port} ] ; then
            match_count=$((${match_count} + 1))
        fi
    done

    if [ ${match_count} -ge 2 ] ; then
        exit 0
    else
        exit 1
    fi
}

while getopts ":kfmps" signal ; do
    case ${signal} in
        s)
            while true ; do
                sleep 0.5
                subscription
                sleep ${update_interval}
            done
            ;;
        k)
            while true ; do
                sleep 10
                keep_dns
                wait
            done
            ;;
        f)
            find_packages_uid
            ;;
        m)
            while true ; do
                sleep 0.5
                monitor_local_ipv4
                wait
            done
            ;;
        p)
            sleep 5
            port_detection
            ;;
        ?)
            echo ""
            ;;
    esac
done