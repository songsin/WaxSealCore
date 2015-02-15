///:
/*****************************************************************************
 **                                                                         **
 **                               .======.                                  **
 **                               | INRI |                                  **
 **                               |      |                                  **
 **                               |      |                                  **
 **                      .========'      '========.                         **
 **                      |   _      xxxx      _   |                         **
 **                      |  /_;-.__ / _\  _.-;_\  |                         **
 **                      |     `-._`'`_/'`.-'     |                         **
 **                      '========.`\   /`========'                         **
 **                               | |  / |                                  **
 **                               |/-.(  |                                  **
 **                               |\_._\ |                                  **
 **                               | \ \`;|                                  **
 **                               |  > |/|                                  **
 **                               | / // |                                  **
 **                               | |//  |                                  **
 **                               | \(\  |                                  **
 **                               |  ``  |                                  **
 **                               |      |                                  **
 **                               |      |                                  **
 **                               |      |                                  **
 **                               |      |                                  **
 **                   \\    _  _\\| \//  |//_   _ \// _                     **
 **                  ^ `^`^ ^`` `^ ^` ``^^`  `^^` `^ `^                     **
 **                                                                         **
 **                       Copyright (c) 2015 Tong G.                        **
 **                          ALL RIGHTS RESERVED.                           **
 **                                                                         **
 ****************************************************************************/

#import "WSCProtectedKeychainItem.h"
#import "WSCTrustedApplication.h"
#import "WSCPermittedOperation.h"
#import "WSCKeychainError.h"

#import "_WSCKeychainErrorPrivate.h"
#import "_WSCKeychainItemPrivate.h"
#import "_WSCProtectedKeychainItemPrivate.h"
#import "_WSCPermittedOperationPrivate.h"

@implementation WSCProtectedKeychainItem

#pragma mark Managing Permitted Operations
/* Creates a new permitted operation entry from the description, trusted application list, and prompt context provided
 * and adds it to the protected keychain item represented by receiver.
 */
- ( WSCPermittedOperation* ) addPermittedOperationWithDescription: ( NSString* )_Description
                                              trustedApplications: ( NSArray* )_TrustedApplications
                                                    forOperations: ( WSCPermittedOperationTag )_Operations
                                                    promptContext: ( WSCPermittedOperationPromptContext )_PromptContext
                                                            error: ( NSError** )_Error
    {
    NSError* error = nil;
    _WSCDontBeABitch( &error, self, [ WSCProtectedKeychainItem class ], s_guard );
    if ( error )
        {
        if ( _Error )
            *_Error = [ error copy ];

        return nil;
        }

    WSCPermittedOperation* newPermitted = nil;
    NSMutableArray* secTrustedApps = nil;

    // Convert the given Cocoa-array of WSCTrustedApplication
    // to the CoreFoundation-array of secTrustedApplicationRef
    if ( _TrustedApplications )
        {
        secTrustedApps = [ NSMutableArray arrayWithCapacity: _TrustedApplications.count ];
        [ _TrustedApplications enumerateObjectsUsingBlock:
            ^( WSCTrustedApplication* _TrustedApp, NSUInteger _Index, BOOL* _Stop )
                {
                [ secTrustedApps addObject: ( __bridge id )_TrustedApp.secTrustedApplication ];
                } ];
        }

    OSStatus resultCode = errSecSuccess;
    SecACLRef secNewACL = NULL;

    SecAccessRef secCurrentAccess = [ self p_secCurrentAccess: _Error ];
    if ( secCurrentAccess )
        {
        // Create the an ALC (Access Control List)
        if ( ( resultCode = SecACLCreateWithSimpleContents( secCurrentAccess
                                                          , ( __bridge CFArrayRef )secTrustedApps
                                                          , ( __bridge CFStringRef )_Description
                                                          , ( SecKeychainPromptSelector )_PromptContext
                                                          , &secNewACL
                                                          ) ) == errSecSuccess )
            {
            // Extract operation tags from the given bits field
            // to construct a list of authorizations that will be used for the secNewACL.
            NSArray* authorizations = [ self p_authorizationsFromPermittedOperationMasks: _Operations ];

            // Update the authorizations of the secNewACL.
            // Because an ACL object is always associated with an access object,
            // when we modify an ACL entry, we are modifying the access object as well.
            // There is no need for a separate function to write a modified ACL object back into the secCurrentAccess object.
            if ( ( resultCode = SecACLUpdateAuthorizations( secNewACL, ( __bridge CFArrayRef )authorizations ) ) == errSecSuccess )
                // Write the modified access object (secCurrentAccess) that carries the secNewACL back into the protected keychain item represented by receiver.
                if ( ( resultCode = SecKeychainItemSetAccess( self.secKeychainItem, secCurrentAccess ) ) == errSecSuccess )
                    // Everything is OK, create the wrapper of the secNewACL that has been added to
                    // the list of permitted operations of the protected keychain item.
                    newPermitted = [ [ [ WSCPermittedOperation alloc ] p_initWithSecACLRef: secNewACL
                                                                                 appliesTo: self
                                                                                     error: _Error ] autorelease ];

            CFRelease( secNewACL );
            }

        CFRelease( secCurrentAccess );
        }

    if ( resultCode != errSecSuccess )
        if ( _Error )
            *_Error = [ NSError errorWithDomain: NSOSStatusErrorDomain code: resultCode userInfo: nil ];

    return newPermitted;
    }

/* Retrieves all the permitted operation entries of the protected keychain item represented by receiver.
 */
- ( NSArray* ) permittedOperations
    {
    NSError* error = nil;
    _WSCDontBeABitch( &error, self, [ WSCProtectedKeychainItem class ], s_guard );
    if ( error )
        {
        _WSCPrintNSErrorForLog( error );
        return nil;
        }

    OSStatus resultCode = errSecSuccess;
    NSMutableArray* mutablePermittedOperations = nil;

    SecAccessRef secCurrentAccess = [ self p_secCurrentAccess: &error ];
    if ( secCurrentAccess )
        {
        CFArrayRef secACLList = NULL;

        // Retrieves all the access control list entries of a given access object.
        if ( ( resultCode = SecAccessCopyACLList( secCurrentAccess, &secACLList ) ) == errSecSuccess )
            {
            mutablePermittedOperations = [ NSMutableArray array ];

            // Convert the given CoreFoundation-array of SecACLRef
            // to the Cocoa-array of WSCPermittedOperation by wrapping them into the WSCPermittedOperation class
            // and adding the wrapper to the mutable array.
            for ( id _SecACL in ( __bridge NSArray* )secACLList )
                {
                WSCPermittedOperation* newPermittedOperation =
                    [ WSCPermittedOperation permittedOperationWithSecACLRef: ( __bridge SecACLRef )_SecACL
                                                                  appliesTo: self
                                                                      error: &error ];
                if ( !error )
                    [ mutablePermittedOperations addObject: newPermittedOperation ];
                }

            CFRelease( secACLList );
            }

        CFRelease( secCurrentAccess );
        }

    if ( resultCode != errSecSuccess )
        {
        error = [ NSError errorWithDomain: NSOSStatusErrorDomain code: resultCode userInfo: nil ];
        _WSCPrintNSErrorForLog( error );
        }

    return [ [ mutablePermittedOperations copy ] autorelease ];
    }

- ( BOOL ) p_isChangeSelfACL: ( SecACLRef )_ACLRef
    {
    BOOL isChangeSelfACL = NO;

    CFArrayRef cfAuthorizations = SecACLCopyAuthorizations( ( __bridge SecACLRef )_ACLRef );
    if ( ( ( __bridge NSArray* )cfAuthorizations ).count == 1
            && [ ( ( __bridge NSArray* )cfAuthorizations ).firstObject isEqualToString: @"ACLAuthorizationChangeACL" ] )
        isChangeSelfACL = YES;

    if ( cfAuthorizations )
        CFRelease( cfAuthorizations );

    return isChangeSelfACL;
    }

- ( SecACLRef ) p_extractChangeSelfACL: ( CFArrayRef )_ArrayOfACLs
    {
    SecACLRef secChangeSelfACL = NULL;

    for ( id _ACLRef in ( __bridge NSArray* )_ArrayOfACLs )
        {
        if ( [ self p_isChangeSelfACL: ( __bridge SecACLRef )_ACLRef ] )
            {
            secChangeSelfACL = ( __bridge SecACLRef )_ACLRef;
            break;
            }
        }

    return secChangeSelfACL;
    }

- ( CFArrayRef ) p_convertACLListFromCFArrayToCocoaArray: ( NSArray* )_PermittedOperations
    {
    NSMutableArray* cfACLList = [ NSMutableArray array ];
    for ( WSCPermittedOperation* _PermittedOperation in _PermittedOperations )
        if ( _PermittedOperation.secACL )
            [ cfACLList addObject: ( __bridge id )_PermittedOperation.secACL ];

    return ( __bridge CFArrayRef )cfACLList;
    }

- ( NSArray* ) setPermittedOperations: ( NSArray* )_NewPermittedOperations
                                error: ( NSError** )_Error;
    {
    OSStatus resultCode = errSecSuccess;
    NSError* error = nil;
    NSArray* olderPermittedOperations = [ self permittedOperations ];

    SecAccessRef currentAccess = [ self p_secCurrentAccess: &error ];
    if ( !error )
        {
        CFArrayRef secCurrentACLList = NULL;

        if ( ( resultCode = SecAccessCopyACLList( currentAccess, &secCurrentACLList ) ) == errSecSuccess )
            {
            NSArray* cocoaCurrentACLList = ( __bridge NSArray* )secCurrentACLList;

            for ( id _ACLRef in cocoaCurrentACLList )
                {
                // If indeed there is a change self ACL
                if ( [ self p_isChangeSelfACL: ( __bridge SecACLRef )_ACLRef ] )
                    {
                    CFArrayRef cfACLList = [ self p_convertACLListFromCFArrayToCocoaArray: _NewPermittedOperations ];
                    SecACLRef changeSelfACLInNewOperations = [ self p_extractChangeSelfACL: cfACLList ];

                    if ( changeSelfACLInNewOperations )
                        {
                        CFStringRef cfDescription = NULL;
                        CFArrayRef cfTrustedApps = NULL;
                        SecKeychainPromptSelector secPromptSel = 0;
                        if ( ( resultCode = SecACLCopyContents( changeSelfACLInNewOperations, &cfTrustedApps, &cfDescription, &secPromptSel ) ) == errSecSuccess )
                            resultCode = SecACLSetContents( ( __bridge SecACLRef )_ACLRef, cfTrustedApps, cfDescription, secPromptSel );
                        }
                    }
                else
                    SecACLRemove( ( __bridge SecACLRef )_ACLRef );
                }

            for ( WSCPermittedOperation* _NewPermittedOperation in _NewPermittedOperations )
                {
                if ( ![ self p_isChangeSelfACL: _NewPermittedOperation.secACL ] )
                    {
                    CFStringRef cfDescription = NULL;
                    CFArrayRef cfTrustedApps = NULL;
                    SecKeychainPromptSelector secPromptSel = 0;
                    if ( ( resultCode = SecACLCopyContents( _NewPermittedOperation.secACL, &cfTrustedApps, &cfDescription, &secPromptSel ) ) == errSecSuccess )
                        resultCode = SecACLCreateWithSimpleContents( currentAccess, cfTrustedApps, cfDescription, secPromptSel, NULL );
                    }
                }

            CFRelease( secCurrentACLList );
            }

        resultCode = SecKeychainItemSetAccess( self.secKeychainItem, currentAccess );

        CFRelease( currentAccess );
        }
    else
        *_Error = [ [ error copy ] autorelease ];

    if ( resultCode != errSecSuccess )
        if ( _Error )
            *_Error = [ NSError errorWithDomain: NSOSStatusErrorDomain code: resultCode userInfo: nil ];

    return olderPermittedOperations;
    }

@end // WSCProtectedKeychainItem

#pragma mark WSCProtectedKeychainItem + WSCProtectedKeychainItemPrivateManagingPermittedOperations
@implementation WSCProtectedKeychainItem ( WSCProtectedKeychainItemPrivateManagingPermittedOperations )

NSUInteger p_permittedOperationTags[] =
    { WSCPermittedOperationTagLogin, WSCPermittedOperationTagGenerateKey, WSCPermittedOperationTagDelete
    , WSCPermittedOperationTagEncrypt, WSCPermittedOperationTagDecrypt
    , WSCPermittedOperationTagExportEncryptedKey, WSCPermittedOperationTagExportUnencryptedKey
    , WSCPermittedOperationTagImportEncryptedKey, WSCPermittedOperationTagImportUnencryptedKey
    , WSCPermittedOperationTagSign, WSCPermittedOperationTagCreateOrVerifyMessageAuthCode
    , WSCPermittedOperationTagDerive, WSCPermittedOperationTagChangePermittedOperationItself
    , WSCPermittedOperationTagChangeOwner, WSCPermittedOperationTagAnyOperation
    };

/* Convert the given Cocoa-array of WSCTrustedApplication
 * to the CoreFoundation-array of secTrustedApplicationRef
 */
- ( NSArray* ) p_authorizationsFromPermittedOperationMasks: ( WSCPermittedOperationTag )_Operations
    {
    NSMutableArray* authorizations = [ NSMutableArray array ];

    if ( ( _Operations & WSCPermittedOperationTagAnyOperation ) != 0 )
        [ authorizations addObject: ( __bridge id )kSecACLAuthorizationAny ];
    else
        {
        int prefinedAuthorizationTags = sizeof( p_permittedOperationTags ) / sizeof( p_permittedOperationTags[ 0 ] );
        for ( int _Index = 0; _Index < prefinedAuthorizationTags; _Index++ )
            {
            if ( ( _Operations & p_permittedOperationTags[ _Index ] ) != 0 )
                {
                switch ( p_permittedOperationTags[ _Index ] )
                    {
                    case WSCPermittedOperationTagLogin: [ authorizations addObject: ( __bridge id )kSecACLAuthorizationLogin ]; break;
                    case WSCPermittedOperationTagGenerateKey: [ authorizations addObject: ( __bridge id )kSecACLAuthorizationGenKey ]; break;
                    case WSCPermittedOperationTagDelete: [ authorizations addObject: ( __bridge id )kSecACLAuthorizationDelete ]; break;
                    case WSCPermittedOperationTagEncrypt: [ authorizations addObject: ( __bridge id )kSecACLAuthorizationEncrypt ]; break;
                    case WSCPermittedOperationTagDecrypt: [ authorizations addObject: ( __bridge id )kSecACLAuthorizationDecrypt ]; break;
                    case WSCPermittedOperationTagExportEncryptedKey: [ authorizations addObject: ( __bridge id )kSecACLAuthorizationExportWrapped ]; break;
                    case WSCPermittedOperationTagExportUnencryptedKey: [ authorizations addObject: ( __bridge id )kSecACLAuthorizationExportClear ]; break;
                    case WSCPermittedOperationTagImportEncryptedKey: [ authorizations addObject: ( __bridge id )kSecACLAuthorizationImportWrapped ]; break;
                    case WSCPermittedOperationTagImportUnencryptedKey: [ authorizations addObject: ( __bridge id )kSecACLAuthorizationImportClear ]; break;
                    case WSCPermittedOperationTagSign: [ authorizations addObject: ( __bridge id )kSecACLAuthorizationSign ]; break;
                    case WSCPermittedOperationTagCreateOrVerifyMessageAuthCode: [ authorizations addObject: ( __bridge id )kSecACLAuthorizationMAC ]; break;
                    case WSCPermittedOperationTagDerive: [ authorizations addObject: ( __bridge id )kSecACLAuthorizationDerive ]; break;
                    case WSCPermittedOperationTagChangePermittedOperationItself: [ authorizations addObject: ( __bridge id )( CFTypeRef )( CFSTR( "ACLAuthorizationChangeACL" ) ) ]; break;
                    case WSCPermittedOperationTagChangeOwner: [ authorizations addObject: ( __bridge id )( CFTypeRef )( CFSTR( "ACLAuthorizationChangeOwner" ) ) ]; break;
                    }
                }
            }
        }

    return [ [ authorizations copy ] autorelease ];
    }

/* Objective-C wrapper of SecKeychainItemCopyAccess() function in Keychain Services
 * Use for copying the access of the protected keychain item represented by receiver.
 */
- ( SecAccessRef ) p_secCurrentAccess: ( NSError** )_Error
    {
    OSStatus resultCode = errSecSuccess;
    SecAccessRef secCurrentAccess = NULL;

    if ( ( resultCode = SecKeychainItemCopyAccess( self.secKeychainItem, &secCurrentAccess ) ) != errSecSuccess )
        if ( _Error )
            *_Error = [ NSError errorWithDomain: NSOSStatusErrorDomain code: resultCode userInfo: nil ];

    return secCurrentAccess;
    }

@end // WSCProtectedKeychainItem + WSCProtectedKeychainItemPrivateManagingPermittedOperations

//////////////////////////////////////////////////////////////////////////////

/*****************************************************************************
 **                                                                         **
 **                                                                         **
 **      █████▒█    ██  ▄████▄   ██ ▄█▀       ██████╗ ██╗   ██╗ ██████╗     **
 **    ▓██   ▒ ██  ▓██▒▒██▀ ▀█   ██▄█▒        ██╔══██╗██║   ██║██╔════╝     **
 **    ▒████ ░▓██  ▒██░▒▓█    ▄ ▓███▄░        ██████╔╝██║   ██║██║  ███╗    **
 **    ░▓█▒  ░▓▓█  ░██░▒▓▓▄ ▄██▒▓██ █▄        ██╔══██╗██║   ██║██║   ██║    **
 **    ░▒█░   ▒▒█████▓ ▒ ▓███▀ ░▒██▒ █▄       ██████╔╝╚██████╔╝╚██████╔╝    **
 **     ▒ ░   ░▒▓▒ ▒ ▒ ░ ░▒ ▒  ░▒ ▒▒ ▓▒       ╚═════╝  ╚═════╝  ╚═════╝     **
 **     ░     ░░▒░ ░ ░   ░  ▒   ░ ░▒ ▒░                                     **
 **     ░ ░    ░░░ ░ ░ ░        ░ ░░ ░                                      **
 **              ░     ░ ░      ░  ░                                        **
 **                    ░                                                    **
 **                                                                         **
 ****************************************************************************/