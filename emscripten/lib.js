mergeInto(LibraryManager.library, {
    getItem: function (keyPtr) {
        let key = Module.UTF8ToString(keyPtr);
        let output = localStorage.getItem(key);
        if (output == null) {
            return null;
        } else {
            let ptr = Module.allocateUTF8(output);
            return ptr;
        }
    },

    setItem: function (keyPtr, valuePtr) {
        let key = Module.UTF8ToString(keyPtr);
        let value = Module.UTF8ToString(valuePtr);
        localStorage.setItem(key, value);
    },
});