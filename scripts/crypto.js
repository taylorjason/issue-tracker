export async function deriveKey(password, saltHex = 'a1b2c3d4e5f60718293a4b5c6d7e8f90') {
    const enc = new TextEncoder();
    const keyMaterial = await crypto.subtle.importKey(
        'raw',
        enc.encode(password),
        { name: 'PBKDF2' },
        false,
        ['deriveBits', 'deriveKey']
    );

    const salt = new Uint8Array(saltHex.match(/.{1,2}/g).map(byte => parseInt(byte, 16)));
    
    return crypto.subtle.deriveKey(
        {
            name: 'PBKDF2',
            salt: salt,
            iterations: 210000,
            hash: 'SHA-256'
        },
        keyMaterial,
        { name: 'AES-GCM', length: 256 },
        false,
        ['encrypt', 'decrypt']
    );
}

export async function encryptData(data, key) {
    if (!key) return data; // Return plaintext if no key
    const enc = new TextEncoder();
    const iv = crypto.getRandomValues(new Uint8Array(12));
    const encrypted = await crypto.subtle.encrypt(
        { name: 'AES-GCM', iv: iv },
        key,
        enc.encode(data)
    );
    
    // Store as base64 JSON payload
    const ivBase64 = btoa(String.fromCharCode(...iv));
    const dataBase64 = btoa(String.fromCharCode(...new Uint8Array(encrypted)));
    return JSON.stringify({ iv: ivBase64, data: dataBase64, enc: true });
}

export async function decryptData(encryptedStr, key) {
    if (!key) return encryptedStr; // Assume plaintext if no key
    try {
        const payload = JSON.parse(encryptedStr);
        if (!payload.enc) return encryptedStr; // It was plaintext

        const iv = new Uint8Array(atob(payload.iv).split('').map(c => c.charCodeAt(0)));
        const dataBytes = new Uint8Array(atob(payload.data).split('').map(c => c.charCodeAt(0)));

        const decrypted = await crypto.subtle.decrypt(
            { name: 'AES-GCM', iv: iv },
            key,
            dataBytes
        );
        const dec = new TextDecoder();
        return dec.decode(decrypted);
    } catch(e) {
        // If it fails to parse as JSON or decrypt, it might just be plaintext
        // or a wrong password error
        if (e.name === 'OperationError') {
            throw new Error('Invalid password or corrupted data');
        }
        return encryptedStr;
    }
}
