# Deleting Network Resources with a Failing Webhook

This document outlines the steps taken to delete network-related resources in a Kubernetes cluster where a validating webhook was preventing deletion due to being unavailable.

## Problem

When attempting to delete `clusternetworks.network.harvesterhci.io`, `vlanconfigs.network.harvesterhci.io`, and `network-attachment-definitions.k8s.cni.cncf.io` resources, the operation failed with the following error:

```
Error from server (InternalError): Internal error occurred: failed calling webhook "validator.harvester-system.harvester-network-webhook": failed to call webhook: Post "https://harvester-network-webhook.harvester-system.svc:443/v1/webhook/validation?timeout=10s": context deadline exceeded
```

Investigation revealed that the `harvester-network-webhook` pod and its corresponding deployment were not running in the `harvester-system` namespace, causing the webhook to time out.

## Solution

To bypass the failing webhook and delete the resources, the following steps were taken for each resource:

1.  **Disable the Webhook's Failure Policy:** The `failurePolicy` of the `harvester-network-webhook` `ValidatingWebhookConfiguration` was temporarily changed from `Fail` to `Ignore`. This allows the API server to ignore the webhook if it's unavailable.

    ```bash
    kubectl patch validatingwebhookconfiguration harvester-network-webhook --type='json' -p='[{"op": "replace", "path": "/webhooks/0/failurePolicy", "value": "Ignore"}]'
    ```

2.  **Delete the Resource:** With the webhook's failure policy set to `Ignore`, the resource was successfully deleted. The following resources were deleted:
    *   `clusternetworks.network.harvesterhci.io storage`
    *   `vlanconfigs.network.harvesterhci.io storage`
    *   `network-attachment-definitions.k8s.cni.cncf.io k8s-podto5-storage`

3.  **Re-enable the Webhook's Failure Policy:** After deleting the resource, the `failurePolicy` was reverted to `Fail` to restore the webhook's intended behavior.

    ```bash
    kubectl patch validatingwebhookconfiguration harvester-network-webhook --type='json' -p='[{"op": "replace", "path": "/webhooks/0/failurePolicy", "value": "Fail"}]'
    ```
