/*=================================================================================================   Copyright (c) 2016 Joel de Guzman   Licensed under a Creative Commons Attribution-ShareAlike 4.0 International.   http://creativecommons.org/licenses/by-sa/4.0/=================================================================================================*/#include <photon/support/canvas.hpp>#include <photon/view.hpp>#include <Quartz/Quartz.h>#include "osx_view_state.hpp"struct canvas_impl;namespace photon{   char const* default_font = "Helvetica Neue";   canvas::canvas(canvas_impl* impl, view& view_)    : _impl(impl)    , _view(view_)   {      // Flip the text drawing vertically      auto ctx = CGContextRef(_impl);      CGAffineTransform trans = CGAffineTransformMakeScale(1, -1);      CGContextSetTextMatrix(ctx, trans);      // Set the default font      font(default_font);   }   void canvas::save()   {      CGContextSaveGState(CGContextRef(_impl));      _view._state = std::make_shared<view_state>(_view._state);      // Set the default font      font(default_font);   }   void canvas::restore()   {      _view._state = _view._state->saved;      CGContextRestoreGState(CGContextRef(_impl));   }   void canvas::begin_path()   {      CGContextBeginPath(CGContextRef(_impl));   }   void canvas::close_path()   {      CGContextClosePath(CGContextRef(_impl));   }   void canvas::fill()   {      CGContextFillPath(CGContextRef(_impl));   }   void canvas::stroke()   {      CGContextStrokePath(CGContextRef(_impl));   }      void canvas::clip()   {      CGContextClip(CGContextRef(_impl));      //CGContextEOClip(CGContextRef(_impl));   }   void canvas::move_to(point p)   {      CGContextMoveToPoint(CGContextRef(_impl), p.x, p.y);   }   void canvas::line_to(point p)   {      CGContextAddLineToPoint(CGContextRef(_impl), p.x, p.y);   }   void canvas::arc_to(point p1, point p2, float radius)   {      CGContextAddArcToPoint(         CGContextRef(_impl),         p1.x, p1.y, p2.x, p2.y, radius      );   }   void canvas::arc(      point p, float radius,      float start_angle, float end_angle,      bool ccw   )   {      CGContextAddArc(         CGContextRef(_impl),         p.x, p.y, radius, start_angle, end_angle, !ccw      );   }   namespace detail   {      void round_rect(canvas& c, rect bounds, float radius)      {         auto x = bounds.left;         auto y = bounds.top;         auto r = bounds.right;         auto b = bounds.bottom;         c.begin_path();         c.move_to(point{ x, y + radius });         c.line_to(point{ x, b - radius });         c.arc_to(point{ x, b }, point{ x + radius, b }, radius);         c.line_to(point{ r - radius, b });         c.arc_to(point{ r, b }, point{ r, b - radius }, radius);         c.line_to(point{ r, y + radius });         c.arc_to(point{ r, y }, point{ r - radius, y }, radius);         c.line_to(point{ x + radius, y });         c.arc_to(point{ x, y }, point{ x, y + radius }, radius);      }   }   void canvas::rect(struct rect r)   {      CGContextAddRect(CGContextRef(_impl), CGRectMake(r.left, r.top, r.width(), r.height()));   }   void canvas::round_rect(struct rect r, float radius)   {      detail::round_rect(*this, r, radius);   }   void canvas::fill_style(color c)   {      CGContextSetRGBFillColor(CGContextRef(_impl), c.red, c.green, c.blue, c.alpha);   }   void canvas::stroke_style(color c)   {      CGContextSetRGBStrokeColor(CGContextRef(_impl), c.red, c.green, c.blue, c.alpha);   }   void canvas::line_width(float w)   {      CGContextSetLineWidth(CGContextRef(_impl), w);   }   void canvas::shadow_style(point p, float blur, color c)   {      CGContextSetShadowWithColor(         CGContextRef(_impl), CGSizeMake(p.x, -p.y), blur,         [            [NSColor               colorWithRed : c.red                      green : c.green                      blue  : c.blue                      alpha : c.alpha            ]            CGColor         ]      );   }   void canvas::fill_rect(struct rect r)   {      CGContextFillRect(CGContextRef(_impl), CGRectMake(r.left, r.top, r.width(), r.height()));   }   void canvas::fill_round_rect(struct rect r, float radius)   {      round_rect(r, radius);      fill();   }   void canvas::stroke_rect(struct rect r)   {      CGContextStrokeRect(CGContextRef(_impl), CGRectMake(r.left, r.top, r.width(), r.height()));   }   void canvas::stroke_round_rect(struct rect r, float radius)   {      round_rect(r, radius);      stroke();   }   void canvas::font(char const* family, float size_, int style_)   {      auto  family_ = [NSString stringWithUTF8String:family];      int   style = 0;      if (style_ & bold)         style |= NSBoldFontMask;      if (style_ & italic)         style |= NSItalicFontMask;      auto font_manager = [NSFontManager sharedFontManager];      auto font =         [font_manager            fontWithFamily : family_                    traits : style                    weight : 5                      size : size_         ];      if (font)      {         CFStringRef keys[] = { kCTFontAttributeName, kCTForegroundColorFromContextAttributeName };         CFTypeRef   values[] = { (__bridge const void*)font, kCFBooleanTrue };         if (_view._state->font_attributes)            CFRelease(_view._state->font_attributes);         _view._state->font_attributes = CFDictionaryCreate(           kCFAllocatorDefault, (const void**)&keys,           (const void**)&values, sizeof(keys) / sizeof(keys[0]),           &kCFTypeDictionaryKeyCallBacks,           &kCFTypeDictionaryValueCallBacks         );      }   }   CFStringRef cf_string(char const* f, char const* l)   {      char* bytes;      std::size_t len = l? (l-f) : strlen(f);      bytes = (char*) CFAllocatorAllocate(CFAllocatorGetDefault(), len, 0);      strncpy(bytes, f, len);      return CFStringCreateWithCStringNoCopy(nullptr, bytes, kCFStringEncodingUTF8, nullptr);   }   namespace detail   {      CTLineRef measure_text(         CGContextRef ctx, view_state const* state       , char const* f, char const* l       , CGFloat width, CGFloat& ascent, CGFloat& descent, CGFloat& leading      )      {         auto text = cf_string(f, l);         auto attr_string =            CFAttributedStringCreate(kCFAllocatorDefault, text, state->font_attributes);         CFRelease(text);         auto line = CTLineCreateWithAttributedString(attr_string);         width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading);         return line;      }      CTLineRef prepare_text(         CGContextRef ctx, view_state const* state       , point& p, char const* f, char const* l      )      {         CGFloat ascent, descent, leading, width;         auto line = measure_text(ctx, state, f, l, width, ascent, descent, leading);         switch (state->text_align & 0x1C)         {            case canvas::top:               p.y += ascent;               break;            case canvas::middle:               p.y += ascent/2 - descent/2;               break;            case canvas::bottom:               p.y -= descent;               break;            default:               break;         }         switch (state->text_align & 0x3)         {            case canvas::center:               p.x -= width/2;               break;            case canvas::right:               p.x -= width;               break;            default:               break;         }         return line;      }   }   void canvas::fill_text(point p, char const* f, char const* l)   {      auto ctx = CGContextRef(_impl);      auto line = detail::prepare_text(ctx, _view._state.get(), p, f, l);      CGContextSetTextPosition(ctx, p.x, p.y);      CGContextSetTextDrawingMode(ctx, kCGTextFill);      CTLineDraw(line, ctx);      CFRelease(line);   }   void canvas::stroke_text(point p, char const* f, char const* l)   {      auto ctx = CGContextRef(_impl);      auto line = detail::prepare_text(ctx, _view._state.get(), p, f, l);      CGContextSetTextPosition(ctx, p.x, p.y);      CGContextSetTextDrawingMode(ctx, kCGTextStroke);      CTLineDraw(line, ctx);      CFRelease(line);   }   canvas::text_metrics canvas::measure_text(char const* f, char const* l)   {      auto ctx = CGContextRef(_impl);      CGFloat ascent, descent, leading, width;      auto line = detail::measure_text(         ctx, _view._state.get(), f, l, width, ascent, descent, leading);      auto bounds = CTLineGetImageBounds(line, ctx);      CFRelease(line);      return canvas::text_metrics      {         float(ascent), float(descent),         float(leading), float(width),         {            float(bounds.origin.x), float(bounds.origin.y),            float(bounds.size.width), float(bounds.size.height)         }      };   }   void canvas::text_align(int align)   {      _view._state->text_align = align;   }}