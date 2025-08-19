# Guida per Aggiungere un Nodo a un Cluster Harvester

Dopo aver consultato la documentazione ufficiale di Harvester, ecco una guida completa e verificata.

Il "cluster token" che cerchi fa parte di un URL di registrazione più ampio. Ecco i metodi per ottenerlo, partendo da quello consigliato.

### Metodo 1: Tramite la UI di Harvester (Consigliato)

Questo è il modo più semplice e sicuro, come indicato dalla struttura della documentazione. La UI genera il comando esatto da eseguire sul nuovo nodo.

1.  Accedi alla dashboard di Harvester.
2.  Nel menu a sinistra, vai su **Hosts**.
3.  Fai clic sul pulsante **Add Host** (Aggiungi Host) in alto a destra.
4.  Verrà visualizzato un comando di registrazione. Copialo e incollalo nella shell del nuovo nodo che vuoi aggiungere al cluster.

Questo comando contiene già l'URL del server e il token necessari per il join.

### Metodo 2: Tramite `kubectl` (Avanzato)

Come hai chiesto, è possibile ottenere l'URL di registrazione tramite `kubectl`. Sebbene questo comando non sia esplicitamente menzionato nella guida utente per questa funzione, interroga la configurazione del cluster dove questo valore è memorizzato, probabilmente per essere usato dalla UI.

Esegui questo comando per estrarre l'URL di registrazione:
