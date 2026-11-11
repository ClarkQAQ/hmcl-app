#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int launchError(NSString *message) {
    fprintf(stderr, "HMCL: %s\n", message.UTF8String);

    [NSApplication sharedApplication];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleCritical;
    alert.messageText = @"无法启动 HMCL";
    alert.informativeText = message;
    [alert addButtonWithTitle:@"好"];
    [alert runModal];
    return EXIT_FAILURE;
}

int main(void) {
    @autoreleasepool {
        NSBundle *bundle = NSBundle.mainBundle;
        NSURL *java = [bundle.builtInPlugInsURL
            URLByAppendingPathComponent:@"ZuluJRE.jre/Contents/Home/bin/java"];
        NSURL *jar = [bundle URLForResource:@"HMCL" withExtension:@"jar"];
        NSURL *icon = [bundle URLForResource:@"HMCL" withExtension:@"icns"];
        NSURL *update = [bundle URLForResource:@"update" withExtension:@"json"];
        NSFileManager *files = NSFileManager.defaultManager;
        if (!java || ![files isExecutableFileAtPath:java.path] || !jar || !icon || !update) {
            return launchError(@"应用包中的 Java 或 HMCL 资源缺失。请重新运行 build.sh。");
        }

        NSString *workingDirectory = [NSHomeDirectory()
            stringByAppendingPathComponent:@"Library/Application Support/hmcl"];
        NSError *directoryError = nil;
        if (![files createDirectoryAtPath:workingDirectory
              withIntermediateDirectories:YES
                               attributes:nil
                                    error:&directoryError]) {
            return launchError([NSString stringWithFormat:@"无法创建数据目录 %@。%@",
                workingDirectory, directoryError.localizedDescription]);
        }
        if (chdir(workingDirectory.fileSystemRepresentation) == -1) {
            int directoryStatus = errno;
            return launchError([NSString stringWithFormat:@"无法进入数据目录 %@。%s",
                workingDirectory, strerror(directoryStatus)]);
        }

        NSString *dockIcon = [@"-Xdock:icon=" stringByAppendingString:icon.path];
        NSString *updateSource = [@"-Dhmcl.update_source.override="
            stringByAppendingString:update.absoluteString];
        const char *javaPath = java.fileSystemRepresentation;
        char *const arguments[] = {
            (char *)javaPath,
            "-Xdock:name=HMCL",
            (char *)dockIcon.UTF8String,
            (char *)updateSource.UTF8String,
            "-jar",
            (char *)jar.fileSystemRepresentation,
            NULL,
        };

        execv(javaPath, arguments);
        int launchStatus = errno;
        return launchError([NSString stringWithFormat:@"无法运行包内 Java。%s", strerror(launchStatus)]);
    }
}
