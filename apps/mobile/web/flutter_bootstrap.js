{{flutter_js}}
{{flutter_build_config}}

const assetsBase = document.querySelector('meta[name="finance-assets-base"]')?.content;
_flutter.loader.load({
  config: assetsBase ? { assetBase: new URL(assetsBase, document.baseURI).href } : {},
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}}
  }
});
