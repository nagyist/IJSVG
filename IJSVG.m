//
//  IJSVGImage.m
//  IconJar
//
//  Created by Curtis Hard on 30/08/2014.
//  Copyright (c) 2014 Curtis Hard. All rights reserved.
//

#import "IJSVG.h"
#import "IJSVGCache.h"

@implementation IJSVG

- (void)dealloc
{
    [_group release], _group = nil;
    [_colors release], _colors = nil;
    [super dealloc];
}

static NSColor * _baseColor = nil;

+ (void)setBaseColor:(NSColor *)color
{
    if( _baseColor != nil )
        [_baseColor release], _baseColor = nil;
    _baseColor = [color retain];
}

+ (NSColor *)baseColor
{
    return _baseColor;
}

+ (id)svgNamed:(NSString *)string
{
    return [[self class] svgNamed:string
                         delegate:nil];
}

+ (id)svgNamed:(NSString *)string
      delegate:(id<IJSVGDelegate>)delegate
{
    NSBundle * bundle = [NSBundle mainBundle];
    NSString * str = nil;
    NSString * ext = [string pathExtension];
    if( ext == nil || ext.length == 0 )
        ext = @"svg";
    if( ( str = [bundle pathForResource:[string stringByDeletingPathExtension]
                                 ofType:ext] ) )
        return [[[self alloc] initWithFile:str
                                  delegate:delegate] autorelease];
    return nil;
}

- (id)initWithFile:(NSString *)file
{
    if( ( self = [self initWithFile:file
                           delegate:nil] ) != nil )
    {
    }
    return self;
}

- (id)initWithFile:(NSString *)file
          delegate:(id<IJSVGDelegate>)delegate
{
    if( ( self = [self initWithFilePathURL:[NSURL fileURLWithPath:file]
                                  delegate:delegate] ) )
    {
    }
    return self;
}

- (id)initWithFilePathURL:(NSURL *)aURL
{
    if( ( self = [self initWithFilePathURL:aURL
                                  delegate:nil] ) != nil )
    {
    }
    return self;
}

- (id)initWithFilePathURL:(NSURL *)aURL
                 delegate:(id<IJSVGDelegate>)delegate
{
    if( [IJSVGCache enabled] )
    {
        IJSVG * svg = nil;
        if( ( svg = [IJSVGCache cachedSVGForFileURL:aURL] ) != nil )
#ifndef __clang_analyzer__
            return [svg retain];
#else
        {}
#endif
    }
    
    if( ( self = [super init] ) != nil )
    {
        _delegate = delegate;
        _group = [[IJSVGParser groupForFileURL:aURL] retain];
        if( [IJSVGCache enabled] )
            [IJSVGCache cacheSVG:self
                         fileURL:aURL];
    }
    return self;
}

- (NSImage *)imageWithSize:(NSSize)aSize
{
    NSImage * im = [[[NSImage alloc] initWithSize:aSize] autorelease];
    [im lockFocus];
    [self drawAtPoint:NSMakePoint( 0.f, 0.f )
                 size:aSize];
    [im unlockFocus];
    return im;
}

- (NSArray *)colors
{
    if( _colors == nil )
    {
        _colors = [[NSMutableArray alloc] init];
        [self _recursiveColors:_group];
    }
    return [[_colors copy] autorelease];
}

- (void)drawAtPoint:(NSPoint)point
               size:(NSSize)aSize
{
    [self drawInRect:NSMakeRect( point.x, point.y, aSize.width, aSize.height )];
}

- (void)drawInRect:(NSRect)rect
{
    
    // prep for draw...
    [self _beginDraw:rect];
    
    // setup the transforms and scale on the main context
    CGContextRef ref = [[NSGraphicsContext currentContext] graphicsPort];
    CGContextSaveGState(ref);
    
    // scale the whole drawing context, but first, we need
    // to translate the context so its centered
    CGFloat tX = round(rect.size.width/2-(_group.size.width/2)*_scale);
    CGFloat tY = round(rect.size.height/2-(_group.size.height/2)*_scale);
    CGContextTranslateCTM( ref, tX, tY );
    CGContextScaleCTM( ref, _scale, _scale );
    
    // apply standard defaults
    [self _applyDefaults:ref
                    node:_group];
    
    // begin draw
    [self _drawGroup:_group
                rect:rect];
    
    CGContextRestoreGState(ref);
}

- (void)_recursiveColors:(IJSVGGroup *)group
{
    if( group.fillColor != nil )
        [self _addColor:group.fillColor];
    if( group.strokeColor != nil )
        [self _addColor:group.strokeColor];
    for( id node in [group children] )
    {
        if( [node isKindOfClass:[IJSVGGroup class]] )
            [self _recursiveColors:node];
        else {
            IJSVGPath * p = (IJSVGPath*)node;
            if( p.fillColor != nil )
                [self _addColor:p.fillColor];
            if( p.strokeColor != nil )
                [self _addColor:p.strokeColor];
        }
    }
}

- (void)_addColor:(NSColor *)color
{
    if( [_colors containsObject:color] || color == [NSColor clearColor] )
        return;
    [_colors addObject:color];
}

- (void)_beginDraw:(NSRect)rect
{
    // in order to correctly fit the the SVG into the
    // rect, we need to work out the ratio scale in order
    // to transform the paths into our viewbox
    NSSize dest = rect.size;
    NSSize source = _group.viewBox.size;
    _scale = MIN(dest.width/source.width,dest.height/source.height);
}

- (void)_drawGroup:(IJSVGGroup *)group
              rect:(NSRect)rect
{
    CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];
    CGContextSaveGState( context );
    
    // perform any transforms
    [self _applyDefaults:context
                    node:group];
    
    dispatch_block_t drawBlock = ^{
        // it could be a group or a path
        for( id child in [group children] )
        {
            if( [child isKindOfClass:[IJSVGPath class]] )
            {
                IJSVGPath * p = (IJSVGPath *)child;
                if( p.clipPath != nil )
                {
                    for( id clip in p.clipPath.children )
                    {
                        if( [clip isKindOfClass:[IJSVGGroup class]] )
                            [self _drawGroup:clip
                                        rect:rect];
                        else {
                            
                            // there is a clip path, save the context
                            CGContextSaveGState( context );
                            
                            // add the clip
                            IJSVGPath * p = (IJSVGPath *)clip;
                            [p.path addClip];
                            
                            // draw the path
                            [self _drawPath:child
                                       rect:rect];
                            
                            // restore the context
                            CGContextRestoreGState( context );
                        }
                    }
                } else {
                    // as its just a path, we can happily
                    // just draw it in the current context
                    [self _drawPath:child
                               rect:rect];
                }
            } else if( [child isKindOfClass:[IJSVGGroup class]] ) {
                
                // if its a group, we recursively call this method
                // to generate the paths required
                [self _drawGroup:child
                            rect:rect];
            }
        }

    };
    
    // group clipping
    if( group.clipPath != nil )
    {
        
        // find the clipped children
        for( id child in group.clipPath.children )
        {
            // if its a group, run this again
            if( [child isKindOfClass:[IJSVGGroup class]] )
                [self _drawGroup:child
                            rect:rect];
            else {
                
                // save the context state
                CGContextSaveGState( context );
                
                // find the path
                IJSVGPath * p = (IJSVGPath *)child;
                
                // clip the context
                [p.path addClip];
                
                // draw the paths
                drawBlock();
                
                // restore again
                CGContextRestoreGState( context );
            }
        }
    } else
        // just draw the block
        drawBlock();
    
    // restore the context
    CGContextRestoreGState(context);
}

- (void)_applyDefaults:(CGContextRef)context
                  node:(IJSVGNode *)node
{
    // the opacity, if its 0, assume its broken
    // so set it to 1.f
    CGFloat opacity = node.opacity;
    if( opacity == 0.f )
        opacity = 1.f;
    
    // scale it
    CGContextSetAlpha( context, opacity );
    
    // perform any transforms
    for( IJSVGTransform * transform in node.transforms )
    {
        [IJSVGTransform performTransform:transform
                               inContext:context];
    }
}

- (void)_drawPath:(IJSVGPath *)path
             rect:(NSRect)rect
{
    // there should be a colour on it...
    // defaults to black if not existant
    CGContextRef ref = [[NSGraphicsContext currentContext] graphicsPort];
    CGContextSaveGState(ref);
    
    // there could be transforms per path
    [self _applyDefaults:ref
                    node:path];
    
    // set the fill color,
    // use the base if its not set
    if( path.fillColor == nil && _baseColor != nil )
        [_baseColor set];
    
    // fill the path
    if( path.fillGradient != nil )
    {
        if( [path.fillGradient isKindOfClass:[IJSVGLinearGradient class]] )
        {
            // linear gradient
            NSGradient * gradient = [path.fillGradient gradient];;
            [gradient drawInBezierPath:path.path
                                 angle:path.fillGradient.angle];
        } else if( [path.fillGradient isKindOfClass:[IJSVGRadialGradient class]] )
        {
            // radial gradient
            // very rudimentary at the moment
            IJSVGRadialGradient * radGrad = (IJSVGRadialGradient *)path.fillGradient;
            [radGrad.gradient drawInBezierPath:path.path
                        relativeCenterPosition:NSZeroPoint];
        }
    } else {
        // no gradient specified
        // just use the color instead
        if( path.fillColor != nil )
        {
            [path.fillColor set];
            [path.path fill];
        } else if( _baseColor != nil ) {

            // is there a base color?
            // this is basically used whenever no color
            // is set, its also set via [IJSVG setBaseColor],
            // this must be defined!
            
            [_baseColor set];
            [path.path fill];
        } else {
            [path.path fill];
        }
    }
    
    // any stroke?
    if( path.strokeColor != nil )
    {
        // default line width is 1
        // if its defined elsewhere, then
        // use that one instead
        CGFloat lineWidth = 1.f;
        if( path.strokeWidth != 0 )
            lineWidth = path.strokeWidth;
        [path.strokeColor setStroke];
        [path.path setLineWidth:lineWidth];
        [path.path stroke];
    }
    
    // restore the graphics state
    CGContextRestoreGState(ref);
    
}

#pragma mark IJSVGParserDelegate

- (BOOL)svgParser:(IJSVGParser *)parser
shouldHandleForeignObject:(IJSVGForeignObject *)foreignObject
{
    if( _delegate == nil )
        return NO;
    if( [_delegate respondsToSelector:@selector(svg:shouldHandleForeignObject:)] )
        return [_delegate svg:self
    shouldHandleForeignObject:foreignObject];
    return NO;
}

- (void)svgParser:(IJSVGParser *)parser
handleForeignObject:(IJSVGForeignObject *)foreignObject
         document:(NSXMLDocument *)document
{
    if( _delegate == nil )
        return;
    if( [_delegate respondsToSelector:@selector(svg:handleForeignObject:document:)] )
        [_delegate svg:self
   handleForeignObject:foreignObject
              document:document];
}

@end
