//
//  Icon.swift
//  FileRing
//
//  Created by Cosmos on 01/11/2025.
//

import SwiftUI

struct Icon: View {
    var body: some View {
        GeometryReader{ proxy in
            VStack(spacing: proxy.size.height/10){
                Capsule()
                    .fill(.blue)
                    .frame(height: proxy.size.height/5)
                
                HStack{
                    Circle()
                        .fill(.blue)
                        .frame(width: proxy.size.height*0.3, height:proxy.size.height*0.3)
                    Capsule()
                        .fill(.blue)
                        .frame(height: proxy.size.height/5)
                }
                .frame(maxHeight: .infinity)
                
                Capsule()
                    .fill(.blue)
                    .frame(height: proxy.size.height/5)
            }
            .padding(.vertical, proxy.size.height/100*3)
        }
    }
}

struct IconWithBackground: View {
    var body: some View {
        GeometryReader{ proxy in
            ZStack{
                RoundedRectangle(cornerRadius: proxy.size.height/4)
                    .fill(.white)
                    .shadow(radius: proxy.size.height/10)
                Icon()
                    .padding(proxy.size.height/5)
            }
        }
        .aspectRatio(1, contentMode: .fit)

    }
}

#Preview {
    ZStack{
        Color.gray

        IconWithBackground()
            .frame(height: 100)


    }
}
