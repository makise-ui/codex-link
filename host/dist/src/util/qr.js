import qrcode from "qrcode-terminal";
export function printPairingPayload(payload) {
    const encoded = JSON.stringify(payload);
    console.log("\nPairing payload (paste into Android app if QR scanning is unavailable):");
    console.log(JSON.stringify(payload, null, 2));
    console.log("\nPairing QR:");
    qrcode.generate(encoded, { small: true }, (qr) => {
        console.log(qr);
    });
}
