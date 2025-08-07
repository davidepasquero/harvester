#!/bin/bash

# Intervallo di raccolta in secondi
COLLECTION_INTERVAL=30

# Abilita il globbing esteso per `shopt -s nullglob` se necessario
shopt -s nullglob

echo "Avvio dello script di raccolta metriche per NVMe-TCP..."

while true; do
    echo "========================================================================="
    echo "RACCOLTA METRICHE - $(date)"
    echo "========================================================================="

    echo "\n### 1. STATISTICHE DI SISTEMA (CPU e Memoria) ###"
    echo "--- CPU (vmstat 1 2) ---"
    vmstat 1 2
    echo "\n--- Memoria (free -h) ---"
    free -h

    echo "\n### 2. STATISTICHE I/O (iostat) ###"
    echo "--- iostat -d -x -k 1 2 ---"
    # Il -N mappa i device name per i LVM
    iostat -d -x -k -N 1 2

    echo "\n### 3. STATISTICHE DI RETE (ip & ss) ###"
    echo "--- Interfacce di rete (contatori) ---"
    ip -s link

    echo "\n--- Statistiche riassuntive TCP (ss -s) ---"
    ss -s

    echo "\n--- Dettagli connessioni TCP (ss -tin) ---"
    ss -tin

    echo "\n### 4. PARAMETRI KERNEL (sysctl e /sys) ###"
    echo "--- Parametri NVMe Core (/sys/module/nvme_core/parameters/) ---"
    # Controlla se il modulo è caricato e la directory esiste
    if [ -d /sys/module/nvme_core/parameters/ ]; then
        for param in /sys/module/nvme_core/parameters/*; do
            echo -n "nvme_core: $(basename "$param") = "
            cat "$param"
        done
    else
        echo "Modulo nvme_core non trovato o parametri non disponibili in /sys."
    fi

    echo "\n--- Parametri NVMe TCP (/sys/module/nvme_tcp/parameters/) ---"
    if [ -d /sys/module/nvme_tcp/parameters/ ]; then
        for param in /sys/module/nvme_tcp/parameters/*; do
            echo -n "nvme_tcp: $(basename "$param") = "
            cat "$param"
        done
    else
        echo "Modulo nvme_tcp non trovato o parametri non disponibili in /sys."
    fi

    echo "\n--- Alcuni parametri di rete importanti (sysctl) ---"
    sysctl net.core.rmem_max \
           net.core.wmem_max \
           net.ipv4.tcp_rmem \
           net.ipv4.tcp_wmem \
           net.ipv4.tcp_congestion_control \
           net.core.netdev_max_backlog

    echo "\n========================================================================="
    echo "Raccolta completata. Prossima raccolta tra $COLLECTION_INTERVAL secondi."
    sleep $COLLECTION_INTERVAL
done
