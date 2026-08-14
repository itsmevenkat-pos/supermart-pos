import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Sends raw bytes straight to a Windows-registered printer's spooler,
/// bypassing the OS print dialog/PDF rendering entirely — this is what
/// makes ESC/POS commands actually reach a USB thermal printer rather than
/// being interpreted as a document to lay out. [printerName] is whatever
/// name the printer shows as in Windows Settings → Printers & Scanners
/// (the exact same string OpenPrinter expects).
///
/// UNTESTED against real hardware — this environment has no physical
/// thermal printer to verify against. The Win32 spooler call sequence
/// below (OpenPrinter → StartDocPrinter → StartPagePrinter → WritePrinter
/// → EndPagePrinter → EndDocPrinter → ClosePrinter) is the standard,
/// documented way to send a raw print job on Windows; if it doesn't reach
/// a specific printer, check that printer's driver is set to accept a
/// "RAW" datatype (some drivers only accept "TEXT" or reject raw jobs from
/// non-elevated processes).
class WindowsPrinter {
  static bool printRawBytes({
    required String printerName,
    required List<int> bytes,
    String documentName = 'SuperMart POS Receipt',
  }) {
    final hPrinter = calloc<HANDLE>();
    final printerNamePtr = printerName.toNativeUtf16();
    Pointer<DOC_INFO_1>? docInfo;
    Pointer<Uint8>? buffer;
    Pointer<Utf16>? docNamePtr;
    Pointer<Utf16>? dataTypePtr;
    Pointer<DWORD>? bytesWritten;

    try {
      if (OpenPrinter(printerNamePtr, hPrinter, nullptr) == 0) {
        return false;
      }
      final printerHandle = hPrinter.value;

      docNamePtr = documentName.toNativeUtf16();
      dataTypePtr = 'RAW'.toNativeUtf16();
      docInfo = calloc<DOC_INFO_1>();
      docInfo.ref.pDocName = docNamePtr;
      docInfo.ref.pOutputFile = nullptr;
      docInfo.ref.pDatatype = dataTypePtr;

      final jobId = StartDocPrinter(printerHandle, 1, docInfo.cast());
      if (jobId == 0) {
        ClosePrinter(printerHandle);
        return false;
      }

      if (StartPagePrinter(printerHandle) == 0) {
        EndDocPrinter(printerHandle);
        ClosePrinter(printerHandle);
        return false;
      }

      buffer = calloc<Uint8>(bytes.length);
      for (var i = 0; i < bytes.length; i++) {
        buffer[i] = bytes[i];
      }
      bytesWritten = calloc<DWORD>();
      final success = WritePrinter(printerHandle, buffer.cast(), bytes.length, bytesWritten);

      EndPagePrinter(printerHandle);
      EndDocPrinter(printerHandle);
      ClosePrinter(printerHandle);

      return success != 0;
    } finally {
      calloc.free(printerNamePtr);
      calloc.free(hPrinter);
      if (docInfo != null) calloc.free(docInfo);
      if (docNamePtr != null) calloc.free(docNamePtr);
      if (dataTypePtr != null) calloc.free(dataTypePtr);
      if (buffer != null) calloc.free(buffer);
      if (bytesWritten != null) calloc.free(bytesWritten);
    }
  }

  /// Lists installed Windows printer names, for a settings picker instead
  /// of asking someone to type the exact name by hand.
  static List<String> listPrinterNames() {
    final names = <String>[];
    final needed = calloc<DWORD>();
    final returned = calloc<DWORD>();
    try {
      // First call with a zero buffer just to learn how many bytes are
      // needed — the standard two-call EnumPrinters pattern.
      EnumPrinters(PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS, nullptr, 4, nullptr, 0, needed, returned);
      if (needed.value == 0) return names;

      final buffer = calloc<Uint8>(needed.value);
      try {
        final ok = EnumPrinters(
            PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS,
            nullptr,
            4,
            buffer.cast(),
            needed.value,
            needed,
            returned);
        if (ok == 0) return names;

        final infoArray = buffer.cast<PRINTER_INFO_4>();
        for (var i = 0; i < returned.value; i++) {
          final info = (infoArray + i).ref;
          if (info.pPrinterName != nullptr) {
            names.add(info.pPrinterName.toDartString());
          }
        }
      } finally {
        calloc.free(buffer);
      }
    } finally {
      calloc.free(needed);
      calloc.free(returned);
    }
    return names;
  }
}
