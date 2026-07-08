import { contextBridge, ipcRenderer } from "electron";

contextBridge.exposeInMainWorld("ragdollDev", {
  getConfig: () => ipcRenderer.invoke("dev:config"),
  getServerStats: () => ipcRenderer.invoke("dev:stats"),
  copyGuestUrl: () => ipcRenderer.invoke("dev:copy-guest-url"),
  openGuestWindow: () => ipcRenderer.invoke("dev:open-guest-window"),
});
