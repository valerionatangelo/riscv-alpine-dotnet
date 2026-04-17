// Hello World on .NET / Alpine / RISC-V
using System.Runtime.InteropServices;

Console.WriteLine("Hello from .NET on RISC-V!");
Console.WriteLine($"  Framework : {RuntimeInformation.FrameworkDescription}");
Console.WriteLine($"  OS        : {RuntimeInformation.OSDescription}");
Console.WriteLine($"  Arch      : {RuntimeInformation.ProcessArchitecture}");
Console.WriteLine($"  RID       : {RuntimeInformation.RuntimeIdentifier}");
